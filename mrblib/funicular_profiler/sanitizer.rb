module Funicular
  module Profiler
    class Sanitizer
      MAX_ATTRIBUTES = 24
      MAX_ARRAY = 16
      MAX_KEY_BYTES = 64
      MAX_NAME_BYTES = 128
      MAX_VALUE_BYTES = 256
      SENSITIVE_PARTS = %w[authorization cookie password token secret body query sql state props].freeze
      INVALID = Object.new.freeze

      attr_reader :truncated_attribute_count, :dropped_attribute_count, :invalid_numeric_count

      def initialize
        reset!
      end

      def reset!
        @truncated_attribute_count = 0
        @dropped_attribute_count = 0
        @invalid_numeric_count = 0
      end

      def name(value)
        truncate(string_value(value), MAX_NAME_BYTES)
      end

      def error_type(value)
        truncate(string_value(value), 128)
      end

      def error_message(value)
        truncate(string_value(value), 512)
      end

      def add_error(attributes, error)
        add_bounded(attributes, "error.type", error_type(error.class.name))
        add_bounded(attributes, "error.message", error_message(error.message))
        attributes
      end

      def attributes(values)
        return {} unless values.is_a?(Hash)

        sanitized = {}
        values.each_with_index do |(raw_key, raw_value), index|
          if index >= MAX_ATTRIBUTES
            @truncated_attribute_count += values.length - MAX_ATTRIBUTES
            break
          end

          key = attribute_key(raw_key)
          if key.nil? || sensitive?(key, raw_value)
            @dropped_attribute_count += 1
            next
          end
          key = truncate(key, MAX_KEY_BYTES)

          value = scalar(raw_value)
          if value.equal?(INVALID)
            @dropped_attribute_count += 1
            next
          end
          sanitized[key] = value
        end
        sanitized
      end

      def truncate(value, max_bytes)
        value = clean_utf8(value)
        return value.dup.freeze if value.bytesize <= max_bytes

        result = String.new
        value.each_char do |character|
          break if result.bytesize + character.bytesize > max_bytes
          result << character
        end
        @truncated_attribute_count += 1
        result.freeze
      end

      private

      def add_bounded(attributes, key, value)
        if attributes.length < MAX_ATTRIBUTES || attributes.key?(key)
          attributes[key] = value
        else
          @truncated_attribute_count += 1
        end
      end

      def attribute_key(value)
        return clean_utf8(value) if value.is_a?(String)
        return value.to_s if value.is_a?(Symbol)
        nil
      end

      def string_value(value)
        return value if value.is_a?(String)
        return value.to_s if value.is_a?(Symbol)
        "unknown"
      end

      def scalar(value)
        case value
        when nil, true, false, Integer
          value
        when Float
          finite?(value) ? value : invalid_number
        when String
          truncate(value, MAX_VALUE_BYTES)
        when Symbol
          truncate(value.to_s, MAX_VALUE_BYTES)
        when Array
          scalar_array(value)
        else
          INVALID
        end
      end

      def scalar_array(values)
        result = []
        values.first(MAX_ARRAY).each do |value|
          item = scalar(value)
          return INVALID if item.equal?(INVALID) || item.is_a?(Array)
          result << item
        end
        @truncated_attribute_count += 1 if values.length > MAX_ARRAY
        result.freeze
      end

      def finite?(value)
        return value.finite? if value.respond_to?(:finite?)
        value == value && (value * 0) == 0
      rescue
        false
      end

      def invalid_number
        @invalid_numeric_count += 1
        INVALID
      end

      def sensitive?(key, value)
        normalized = key.downcase
        parts = []
        %w[. - / :].each { |separator| parts += normalized.split(separator) }
        counter = normalized.end_with?("_count") && (value.is_a?(Integer) || value.is_a?(Float))
        parts += normalized.split("_") unless counter
        SENSITIVE_PARTS.include?(normalized) || parts.any? { |part| SENSITIVE_PARTS.include?(part) }
      end

      def clean_utf8(value)
        return value unless value.respond_to?(:valid_encoding?)
        return value if value.valid_encoding? && (!value.respond_to?(:encoding) || value.encoding.to_s == "UTF-8")

        clean = value.dup
        clean.force_encoding("UTF-8") if clean.respond_to?(:force_encoding)
        clean.valid_encoding? ? clean : clean.scrub
      end
    end
  end
end
