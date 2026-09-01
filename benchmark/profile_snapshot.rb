# frozen_string_literal: true

require "json"
require_relative "../mrblib/funicular_profiler/sanitizer"
require_relative "../mrblib/funicular_profiler/record"
require_relative "../mrblib/funicular_profiler/buffer"
require_relative "../mrblib/funicular_profiler/aggregator"
require_relative "../mrblib/funicular_profiler/adapter"

module Funicular
  module Profiler
    SCHEMA_VERSION = 1
    TARGET_JSON_BYTES = 61_440
    MAX_JSON_BYTES = 65_535
  end
end

SnapshotSpan = Struct.new(
  :id, :parent_id, :name, :started_at_us, :attributes, :ended_at_us, :status, :error,
  keyword_init: true
)

adapter = Funicular::Profiler::Adapter.new
probe = SnapshotSpan.new(
  id: 0, parent_id: nil, name: "work", started_at_us: 0,
  ended_at_us: 10, status: :ok, error: nil, attributes: {}
)
started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
2_000.times { adapter.start(probe, nil) }
stopped_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

adapter.start_recording!
started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
2_000.times do |index|
  item = SnapshotSpan.new(
    id: index, parent_id: nil, name: "work", started_at_us: index,
    ended_at_us: index + 10, status: :ok, error: nil,
    attributes: { "funicular.component.class" => "Example" }
  )
  adapter.finish(adapter.start(item, nil), item)
end
recording_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

iterations = Integer(ENV.fetch("ITERATIONS", "1000"))
started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
iterations.times { adapter.snapshot_json(0, 200) }
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
puts JSON.pretty_generate(
  "schema_version" => 1,
  "benchmark" => "profile_snapshot",
  "ruby" => { "engine" => RUBY_ENGINE, "version" => RUBY_VERSION, "platform" => RUBY_PLATFORM },
  "measurements" => {
    "stopped_seconds_per_span" => stopped_elapsed.fdiv(2_000),
    "recording_seconds_per_span" => recording_elapsed.fdiv(2_000),
    "snapshot_seconds_per_call" => elapsed.fdiv(iterations)
  },
  "context" => {
    "spans" => 2_000,
    "snapshots" => iterations,
    "snapshot_bytes" => adapter.snapshot_json(0, 200).bytesize
  }
)
