module Funicular
  module Profiler
    SCHEMA_VERSION = 1
    TARGET_JSON_BYTES = 61_440
    MAX_JSON_BYTES = 65_535
    ADAPTER_NAME = :profiler

    class AlreadyInstalledError < StandardError; end
    class UnsupportedFunicularError < StandardError; end

    class << self
      def install!(capacity: 2_000, max_in_flight: 256, enabled: nil)
        enabled = default_enabled? if enabled.nil?
        configuration = [capacity, max_in_flight, enabled]
        if installed?
          return self if @configuration == configuration
          raise AlreadyInstalledError, "uninstall the existing profiler before changing its configuration"
        end

        verify_funicular!
        adapter = Adapter.new(capacity: capacity, max_in_flight: max_in_flight)
        Funicular::Instrumentation.register(ADAPTER_NAME, adapter)
        @adapter = adapter
        @configuration = configuration
        @adapter.start_recording! if enabled
        export_debug_global
        self
      end

      def installed?
        !@adapter.nil?
      end

      def start!
        @adapter&.start_recording!
        self
      end

      def stop!
        @adapter&.stop_recording!
        self
      end

      def recording?
        !!(@adapter && @adapter.recording?)
      end

      def clear!
        @adapter&.clear!
        self
      end

      def uninstall!
        return self unless @adapter
        @adapter.shutdown
        Funicular::Instrumentation.unregister(ADAPTER_NAME)
        @adapter = nil
        @configuration = nil
        $__funicular_profiler__ = nil
        self
      end

      def snapshot(after_seq: 0, limit: 200)
        active_adapter.snapshot(after_seq: after_seq, limit: limit)
      end

      def snapshot_json(after_seq = 0, limit = 200)
        active_adapter.snapshot_json(after_seq, limit)
      end

      def summary
        active_adapter.summary
      end

      def summary_json
        active_adapter.summary_json
      end

      private

      def active_adapter
        raise UnsupportedFunicularError, "Funicular::Profiler is not installed" unless @adapter
        @adapter
      end

      def verify_funicular!
        api = defined?(Funicular::Instrumentation) && Funicular::Instrumentation
        supported = api && api.const_defined?(:SCHEMA_VERSION) && api::SCHEMA_VERSION == SCHEMA_VERSION
        supported &&= %i[register unregister registered?].all? { |name| api.respond_to?(name) }
        return if supported
        raise UnsupportedFunicularError, "Funicular instrumentation schema version 1 is required"
      end

      def default_enabled?
        return false unless Funicular.respond_to?(:server?) && !Funicular.server?
        Funicular.respond_to?(:env) && Funicular.env.respond_to?(:development?) && Funicular.env.development?
      rescue
        false
      end

      def export_debug_global
        return unless default_enabled?
        $__funicular_profiler__ = self
      end
    end
  end
end
