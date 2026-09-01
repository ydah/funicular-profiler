module Funicular
  module Profiler
    class Adapter
      MIN_IN_FLIGHT = 16
      MAX_IN_FLIGHT = 4_096

      class State
        attr_reader :key, :id, :parent_id, :name, :started_at_us, :attributes

        def initialize(key, id, parent_id, name, started_at_us, attributes)
          @key = key
          @id = immutable_string(id)
          @parent_id = immutable_string(parent_id)
          @name = immutable_string(name)
          @started_at_us = started_at_us
          @attributes = attributes.freeze
          @finished = false
        end

        def finished?
          @finished
        end

        def finish!
          return false if @finished
          @finished = true
          true
        end

        private

        def immutable_string(value)
          value.is_a?(String) && !value.frozen? ? value.dup.freeze : value
        end
      end

      class DroppedState
        def finished?
          true
        end
      end

      DROPPED_STATE = DroppedState.new

      attr_reader :buffer, :sanitizer, :dropped_in_flight_count,
                  :adapter_error_count, :corrupt_record_count, :max_in_flight

      def initialize(capacity: 2_000, max_in_flight: 256, clock: nil)
        unless max_in_flight.is_a?(Integer) && max_in_flight.between?(MIN_IN_FLIGHT, MAX_IN_FLIGHT)
          raise ArgumentError, "max_in_flight must be between #{MIN_IN_FLIGHT} and #{MAX_IN_FLIGHT}"
        end
        @buffer = Buffer.new(capacity)
        @sanitizer = Sanitizer.new
        @max_in_flight = max_in_flight
        @clock = clock
        @in_flight = {}
        @state_sequence = 0
        @event_sequence = 0
        @recording = false
        reset_counters
      end

      def enabled?(_event_name = nil)
        @recording
      end

      def recording?
        @recording
      end

      def start_recording!
        @recording = true
        self
      end

      def stop_recording!
        return self unless @recording || !@in_flight.empty?
        @recording = false
        cancel_in_flight
        self
      end

      def start(span, parent_state)
        return DROPPED_STATE unless @recording
        if @in_flight.length >= max_in_flight
          @dropped_in_flight_count += 1
          return DROPPED_STATE
        end

        @state_sequence += 1
        state = State.new(
          @state_sequence,
          span_id(span.id),
          parent_state.is_a?(State) ? parent_state.id : parent_id(span.parent_id),
          sanitizer.name(span.name),
          span.started_at_us.to_i,
          sanitizer.attributes(span.attributes)
        )
        @in_flight[state.key] = state
        state
      rescue
        @adapter_error_count += 1
        DROPPED_STATE
      end

      def finish(state, span)
        return nil unless state.is_a?(State) && state.finish!
        @in_flight.delete(state.key)
        attributes = sanitizer.attributes(span.attributes)
        sanitizer.add_error(attributes, span.error) if span.error
        insert_record(
          kind: "span", id: state.id, parent_id: state.parent_id, name: state.name,
          started_at_us: state.started_at_us,
          duration_us: span.ended_at_us.to_i - state.started_at_us,
          status: span.status || :ok, attributes: attributes
        )
        nil
      rescue
        @adapter_error_count += 1
        nil
      end

      def event(event)
        return nil unless @recording
        @event_sequence += 1
        name = sanitizer.name(event.name)
        insert_record(
          kind: "event", id: "e-#{event.sequence || @event_sequence}",
          parent_id: parent_id(event.parent_id), name: name,
          started_at_us: event.occurred_at_us.to_i, duration_us: 0,
          status: error_event?(name) ? "error" : "ok",
          attributes: sanitizer.attributes(event.attributes)
        )
        nil
      rescue
        @adapter_error_count += 1
        nil
      end

      def clear!
        buffer.clear!
        sanitizer.reset!
        reset_counters
        self
      end

      def snapshot(after_seq: 0, limit: 200)
        page = buffer.page(after_seq, limit)
        records = []
        page[:records].each do |record|
          begin
            records << record.to_h
          rescue
            @corrupt_record_count += 1
          end
        end
        snapshot_hash(page, records)
      rescue
        @adapter_error_count += 1
        error_snapshot
      end

      def snapshot_json(after_seq = 0, limit = 200)
        bounded_json(snapshot(after_seq: after_seq, limit: limit), "records")
      rescue
        @adapter_error_count += 1
        JSON.generate(error_snapshot)
      end

      def summary
        {
          "schema_version" => Profiler::SCHEMA_VERSION,
          "session_id" => buffer.session_id,
          "recording" => recording?,
          "record_count" => buffer.size,
          "dropped_count" => buffer.dropped_count,
          "groups" => Aggregator.new.summarize(buffer)
        }
      rescue
        @adapter_error_count += 1
        error_snapshot("summary_failed", "Profiler summary could not be generated")
      end

      def summary_json
        bounded_json(summary, "groups", "summary_failed", "Profiler summary could not be generated")
      rescue
        @adapter_error_count += 1
        JSON.generate(error_snapshot("summary_failed", "Profiler summary could not be generated"))
      end

      def flush
        nil
      end

      def shutdown
        stop_recording!
        nil
      end

      private

      def bounded_json(payload, array_key, error = "snapshot_failed", message = "Profiler snapshot could not be generated")
        json = JSON.generate(payload)
        return json if json.bytesize <= Profiler::TARGET_JSON_BYTES

        items = payload.fetch(array_key)
        payload["response_truncated"] = true
        payload["has_more"] = true if array_key == "records"
        low = 0
        high = items.length
        while low < high
          middle = (low + high + 1) / 2
          payload[array_key] = items.first(middle)
          update_next_cursor(payload) if array_key == "records"
          if JSON.generate(payload).bytesize <= Profiler::TARGET_JSON_BYTES
            low = middle
          else
            high = middle - 1
          end
        end
        payload[array_key] = items.first(low)
        update_next_cursor(payload) if array_key == "records"
        json = JSON.generate(payload)
        return json if json.bytesize <= Profiler::MAX_JSON_BYTES
        JSON.generate(error_snapshot(error, message))
      end

      def update_next_cursor(payload)
        records = payload["records"]
        payload["next_cursor"] = records.empty? ? payload["cursor"] : records[-1]["seq"]
      end

      def insert_record(**fields)
        buffer.insert(Record.new(**fields))
      end

      def cancel_in_flight
        ended_at = now_us
        @in_flight.values.each do |state|
          next unless state.finish!
          insert_record(
            kind: "span", id: state.id, parent_id: state.parent_id, name: state.name,
            started_at_us: state.started_at_us, duration_us: ended_at - state.started_at_us,
            status: "cancelled", attributes: state.attributes
          )
        rescue
          @adapter_error_count += 1
        end
        @in_flight = {}
      end

      def now_us
        return @clock.call if @clock
        browser = Funicular.respond_to?(:server?) && !Funicular.server?
        if browser && defined?(JS) && JS.respond_to?(:global)
          return (JS.global[:performance].now.to_f * 1_000).to_i
        end
        return Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) if defined?(Process::CLOCK_MONOTONIC)
        (Time.now.to_f * 1_000_000).to_i
      rescue
        (Time.now.to_f * 1_000_000).to_i
      end

      def span_id(id)
        id.is_a?(String) ? id : "s-#{id}"
      end

      def parent_id(id)
        return nil if id.nil?
        id.is_a?(String) ? id : "s-#{id}"
      end

      def error_event?(name)
        name == "funicular.error" || name == "funicular.hydration.fallback"
      end

      def snapshot_hash(page, records)
        {
          "schema_version" => Profiler::SCHEMA_VERSION,
          "session_id" => buffer.session_id,
          "recording" => recording?,
          "cursor" => page[:cursor],
          "next_cursor" => page[:next_cursor],
          "oldest_seq" => page[:oldest_seq],
          "newest_seq" => page[:newest_seq],
          "cursor_gap" => page[:cursor_gap],
          "has_more" => page[:has_more],
          "dropped_count" => buffer.dropped_count,
          "dropped_in_flight_count" => dropped_in_flight_count,
          "truncated_attribute_count" => sanitizer.truncated_attribute_count,
          "dropped_attribute_count" => sanitizer.dropped_attribute_count,
          "invalid_numeric_count" => sanitizer.invalid_numeric_count,
          "adapter_error_count" => adapter_error_count,
          "corrupt_record_count" => corrupt_record_count,
          "records" => records
        }
      end

      def error_snapshot(error = "snapshot_failed", message = "Profiler snapshot could not be generated")
        { "schema_version" => Profiler::SCHEMA_VERSION, "error" => error, "message" => message }
      end

      def reset_counters
        @dropped_in_flight_count = 0
        @adapter_error_count = 0
        @corrupt_record_count = 0
      end
    end
  end
end
