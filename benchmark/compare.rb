# frozen_string_literal: true

require "json"

def compare(baseline, current)
  raise ArgumentError, "unsupported benchmark schema" unless baseline["schema_version"] == 1 && current["schema_version"] == 1

  name = baseline.fetch("benchmark")
  raise ArgumentError, "benchmark names differ" unless current.fetch("benchmark") == name

  measurements = baseline.fetch("measurements").keys & current.fetch("measurements").keys
  raise ArgumentError, "no common measurements" if measurements.empty?

  comparisons = measurements.to_h do |measurement|
    before = baseline["measurements"].fetch(measurement)
    after = current["measurements"].fetch(measurement)
    raise ArgumentError, "measurements must be numeric and baseline must be positive" unless before.is_a?(Numeric) && before.positive? && after.is_a?(Numeric)

    ratio = after.fdiv(before)
    [measurement, { "baseline" => before, "current" => after, "ratio" => ratio, "change_percent" => (ratio - 1) * 100 }]
  end
  { "schema_version" => 1, "benchmark" => name, "comparisons" => comparisons }
end

if ARGV == ["--self-test"]
  result = compare(
    { "schema_version" => 1, "benchmark" => "probe", "measurements" => { "seconds" => 2.0 } },
    { "schema_version" => 1, "benchmark" => "probe", "measurements" => { "seconds" => 3.0 } }
  )
  raise "comparison self-test failed" unless result.dig("comparisons", "seconds", "ratio") == 1.5
  puts "comparison self-test passed"
elsif ARGV.length == 2
  puts JSON.pretty_generate(compare(JSON.parse(File.read(ARGV[0])), JSON.parse(File.read(ARGV[1]))))
else
  abort "usage: ruby benchmark/compare.rb BASELINE.json CURRENT.json"
end
