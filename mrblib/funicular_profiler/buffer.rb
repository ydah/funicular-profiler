module Funicular
  module Profiler
    class Buffer
      MIN_CAPACITY = 100
      MAX_CAPACITY = 20_000
      MAX_PAGE = 200

      attr_reader :capacity, :size, :dropped_count, :session_id

      def initialize(capacity = 2_000)
        unless capacity.is_a?(Integer) && capacity.between?(MIN_CAPACITY, MAX_CAPACITY)
          raise ArgumentError, "capacity must be between #{MIN_CAPACITY} and #{MAX_CAPACITY}"
        end
        @capacity = capacity
        @session_id = 1
        reset
      end

      def insert(record)
        stored = record.with_seq(@next_seq)
        @next_seq += 1
        @dropped_count += 1 if @size == capacity
        @records[@head] = stored
        @head = (@head + 1) % capacity
        @size += 1 if @size < capacity
        stored
      end

      def page(after_seq, limit)
        cursor = integer_or_zero(after_seq)
        page_limit = [[integer_or_zero(limit), 1].max, MAX_PAGE].min
        selected = []
        each_record do |record|
          next unless record.seq > cursor
          selected << record
          break if selected.length > page_limit
        end
        has_more = selected.length > page_limit
        selected.pop if has_more
        {
          records: selected,
          cursor: cursor,
          next_cursor: selected.empty? ? cursor : selected[-1].seq,
          oldest_seq: oldest_seq,
          newest_seq: newest_seq,
          cursor_gap: !oldest_seq.nil? && cursor < oldest_seq - 1,
          has_more: has_more
        }
      end

      def each_record
        return self unless block_given?
        index = @size == capacity ? @head : 0
        count = 0
        while count < @size
          yield @records[index]
          index = (index + 1) % capacity
          count += 1
        end
      end

      def oldest_seq
        return nil if @size == 0
        @records[@size == capacity ? @head : 0].seq
      end

      def newest_seq
        return nil if @size == 0
        @records[(@head - 1) % capacity].seq
      end

      def clear!
        @session_id += 1
        reset
      end

      private

      def reset
        @records = Array.new(capacity)
        @head = 0
        @size = 0
        @next_seq = 1
        @dropped_count = 0
      end

      def integer_or_zero(value)
        value.to_i
      rescue
        0
      end
    end
  end
end
