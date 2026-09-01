# frozen_string_literal: true

require_relative "test_helper"

class SanitizerTest < Minitest::Test
  class Hostile
    def inspect
      raise "inspect must not be called"
    end
  end

  def test_scalars_bounds_sensitive_keys_and_no_inspect
    sanitizer = Funicular::Profiler::Sanitizer.new
    attributes = sanitizer.attributes(
      "nil" => nil,
      "bool" => true,
      "integer" => 1,
      "float" => 1.5,
      "symbol" => :ready,
      "array" => [1, "two", false],
      "token_count" => 3,
      "password_count" => "secret",
      "csrf_token" => "secret",
      "http/request/body" => "secret",
      "#{"a" * 64}.token" => "secret",
      "http.authorization" => "secret",
      "object" => Hostile.new,
      "long" => "あ" * 100
    )

    assert_equal 3, attributes["token_count"]
    refute attributes.key?("password_count")
    refute attributes.key?("http.authorization")
    refute attributes.key?("csrf_token")
    refute attributes.key?("http/request/body")
    refute attributes.key?("a" * 64)
    refute attributes.key?("object")
    assert_operator attributes["long"].bytesize, :<=, 256
    assert_equal "ready", attributes["symbol"]
    assert_equal [1, "two", false], attributes["array"]
    assert_operator sanitizer.dropped_attribute_count, :>=, 2
  end

  def test_non_finite_arrays_count_and_invalid_utf8
    sanitizer = Funicular::Profiler::Sanitizer.new
    invalid = "ok\xFF".dup.force_encoding(Encoding::UTF_8)
    binary = "\xFF".b
    values = {
      "nan" => Float::NAN, "infinity" => Float::INFINITY,
      "invalid" => invalid, "binary" => binary
    }
    30.times { |index| values["key_#{index}"] = index }
    attributes = sanitizer.attributes(values)

    refute attributes.key?("nan")
    refute attributes.key?("infinity")
    assert attributes["invalid"].valid_encoding?
    assert attributes["binary"].valid_encoding?
    JSON.generate(attributes)
    assert_operator attributes.length, :<=, 24
    assert_equal 2, sanitizer.invalid_numeric_count
    assert_operator sanitizer.truncated_attribute_count, :>, 0
  end
end
