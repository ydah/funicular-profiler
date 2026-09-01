module Funicular
  module Profiler
    class Record
      SCHEMA_VERSION = 1
      KINDS = %w[span event].freeze
      STATUSES = %w[ok error cancelled].freeze

      attr_reader :seq, :kind, :id, :parent_id, :name, :started_at_us,
                  :duration_us, :status, :attributes

      def initialize(kind:, id:, parent_id:, name:, started_at_us:, duration_us:, status:, attributes:, seq: nil)
        kind = kind.to_s
        status = status.to_s
        raise ArgumentError, "unknown record kind: #{kind}" unless KINDS.include?(kind)
        raise ArgumentError, "unknown record status: #{status}" unless STATUSES.include?(status)

        @seq = seq
        @kind = immutable_string(kind)
        @id = immutable_string(id)
        @parent_id = immutable_string(parent_id)
        @name = immutable_string(name)
        @started_at_us = started_at_us.to_i
        @duration_us = [duration_us.to_i, 0].max
        @status = immutable_string(status)
        @attributes = immutable_attributes(attributes)
      end

      def with_seq(seq)
        self.class.new(
          seq: seq, kind: kind, id: id, parent_id: parent_id, name: name,
          started_at_us: started_at_us, duration_us: duration_us,
          status: status, attributes: attributes
        )
      end

      def to_h
        {
          "schema_version" => SCHEMA_VERSION,
          "seq" => seq,
          "kind" => kind,
          "id" => id,
          "parent_id" => parent_id,
          "name" => name,
          "started_at_us" => started_at_us,
          "duration_us" => duration_us,
          "status" => status,
          "attributes" => attributes
        }
      end

      private

      def immutable_attributes(attributes)
        copy = {}
        attributes.each do |key, value|
          key = immutable_string(key)
          value = value.map { |item| immutable_string(item) }.freeze if value.is_a?(Array)
          copy[key] = immutable_string(value)
        end
        copy.freeze
      end

      def immutable_string(value)
        value.is_a?(String) && !value.frozen? ? value.dup.freeze : value
      end
    end
  end
end
