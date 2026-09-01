# frozen_string_literal: true

require "json"
require_relative "../mrblib/funicular_profiler/record"
require_relative "../mrblib/funicular_profiler/buffer"

record = Funicular::Profiler::Record.new(
  kind: "span", id: "s-1", parent_id: nil, name: "work",
  started_at_us: 1, duration_us: 1, status: "ok", attributes: {}
)
iterations = Integer(ENV.fetch("ITERATIONS", "100000"))
buffer = Funicular::Profiler::Buffer.new(2_000)

started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
iterations.times { buffer.insert(record) }
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
puts JSON.pretty_generate(
  "schema_version" => 1,
  "benchmark" => "profile_buffer",
  "ruby" => { "engine" => RUBY_ENGINE, "version" => RUBY_VERSION, "platform" => RUBY_PLATFORM },
  "measurements" => { "insert_seconds_per_record" => elapsed.fdiv(iterations) },
  "context" => { "records" => iterations, "retained" => buffer.size, "dropped" => buffer.dropped_count }
)
