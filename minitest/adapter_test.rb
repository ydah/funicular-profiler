# frozen_string_literal: true

require_relative "test_helper"

class AdapterTest < Minitest::Test
  def test_span_event_parent_error_and_summary
    adapter = Funicular::Profiler::Adapter.new(capacity: 100, clock: -> { 500 })
    adapter.start_recording!
    parent_state = adapter.start(span(id: 1, name: "parent", attributes: { "funicular.component.class" => "List" }), nil)
    child = span(
      id: 2, parent_id: 1, name: "funicular.component.update", started_at_us: 120,
      ended_at_us: 220, status: :error, error: ArgumentError.new("bad input"),
      attributes: { "funicular.component.class" => "List", "funicular.diff.empty" => true }
    )
    child_state = adapter.start(child, parent_state)
    adapter.finish(child_state, child)
    adapter.event(FakeEvent.new(
      sequence: 3, name: "funicular.hydration.fallback", occurred_at_us: 230,
      attributes: { "reason" => "root_tag_mismatch" }, parent_id: 1
    ))
    parent = span(id: 1, name: "parent", ended_at_us: 300, attributes: { "funicular.component.class" => "List" })
    adapter.finish(parent_state, parent)

    records = adapter.snapshot(after_seq: 0, limit: 200)["records"]
    assert_equal %w[s-2 e-3 s-1], records.map { |record| record["id"] }
    assert_equal "s-1", records[0]["parent_id"]
    assert_equal "error", records[0]["status"]
    assert_equal "ArgumentError", records[0]["attributes"]["error.type"]
    assert_equal "error", records[1]["status"]

    group = adapter.summary["groups"].find { |item| item["name"] == "funicular.component.update" }
    assert_equal 1, group["count"]
    assert_equal 1, group["error_count"]
    assert_equal 1, group["empty_diff_count"]
    assert_equal 100, group["p95_us"]
  end

  def test_in_flight_bound_stop_cancellation_and_late_finish
    adapter = Funicular::Profiler::Adapter.new(capacity: 100, max_in_flight: 16, clock: -> { 500 })
    adapter.start_recording!
    states = 17.times.map { |index| adapter.start(span(id: index + 1, started_at_us: 100), nil) }
    assert_equal 1, adapter.dropped_in_flight_count

    adapter.stop_recording!
    assert_equal 16, adapter.buffer.size
    assert adapter.snapshot["records"].all? { |record| record["status"] == "cancelled" }
    adapter.finish(states.first, span(id: 1, ended_at_us: 700))
    assert_equal 16, adapter.buffer.size
    refute adapter.enabled?("work")
  end

  def test_finish_keeps_attribute_bound_with_error_metadata
    adapter = Funicular::Profiler::Adapter.new(capacity: 100)
    adapter.start_recording!
    attributes = {}
    24.times { |index| attributes["key_#{index}"] = index }
    item = span(id: 1, attributes: attributes, status: :error, error: RuntimeError.new("boom"))
    adapter.finish(adapter.start(item, nil), item)

    assert_equal 24, adapter.snapshot["records"][0]["attributes"].length
  end

  def test_summary_uses_nearest_rank_percentiles
    adapter = Funicular::Profiler::Adapter.new(capacity: 100)
    adapter.start_recording!
    [10, 20, 30, 40].each_with_index do |duration, index|
      item = span(id: index + 1, started_at_us: 0, ended_at_us: duration)
      adapter.finish(adapter.start(item, nil), item)
    end
    group = adapter.summary["groups"][0]

    assert_equal 20, group["p50_us"]
    assert_equal 40, group["p95_us"]
  end

  def test_in_flight_state_owns_bounded_input
    adapter = Funicular::Profiler::Adapter.new(capacity: 100, clock: -> { 200 })
    adapter.start_recording!
    name = +"work"
    value = +"safe"
    item = span(id: 1, name: name, attributes: { "value" => value })
    adapter.start(item, nil)
    name << " changed"
    value << " changed"

    adapter.stop_recording!
    record = adapter.snapshot["records"][0]
    assert_equal "work", record["name"]
    assert_equal "safe", record["attributes"]["value"]
  end
end
