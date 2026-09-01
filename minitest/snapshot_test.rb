# frozen_string_literal: true

require_relative "test_helper"

class SnapshotTest < Minitest::Test
  def test_schema_cursor_json_limit_and_session
    adapter = Funicular::Profiler::Adapter.new(capacity: 300)
    adapter.start_recording!
    250.times do |index|
      item = span(
        id: index + 1, started_at_us: index, ended_at_us: index + 10,
        attributes: { "value" => "x" * 256 }
      )
      adapter.finish(adapter.start(item, nil), item)
    end

    json = adapter.snapshot_json(0, 200)
    payload = JSON.parse(json)
    assert_operator json.bytesize, :<=, 65_535
    assert_equal 1, payload["schema_version"]
    assert payload["response_truncated"]
    assert payload["has_more"]
    assert_operator payload["records"].length, :<, 200

    session = payload["session_id"]
    adapter.clear!
    assert_equal session + 1, adapter.snapshot["session_id"]
    assert adapter.recording?
  end

  def test_group_limit
    adapter = Funicular::Profiler::Adapter.new(capacity: 600)
    adapter.start_recording!
    501.times do |index|
      item = span(id: index + 1, name: "group-#{index}")
      adapter.finish(adapter.start(item, nil), item)
    end
    groups = adapter.summary["groups"]
    assert_equal 500, groups.length
    assert groups.any? { |group| group["name"] == "<other>" }
  end

  def test_exact_group_limit_does_not_fold_a_group_early
    adapter = Funicular::Profiler::Adapter.new(capacity: 600)
    adapter.start_recording!
    500.times do |index|
      item = span(id: index + 1, name: "group-#{index}")
      adapter.finish(adapter.start(item, nil), item)
    end

    groups = adapter.summary["groups"]
    assert_equal 500, groups.length
    refute groups.any? { |group| group["name"] == "<other>" }
  end

  def test_summary_json_fits_the_debug_bridge_buffer
    adapter = Funicular::Profiler::Adapter.new(capacity: 600)
    adapter.start_recording!
    500.times do |index|
      item = span(
        id: index + 1,
        name: "operation-#{index}-#{"n" * 128}",
        attributes: { "funicular.component.class" => "c" * 256 }
      )
      adapter.finish(adapter.start(item, nil), item)
    end

    json = adapter.summary_json
    payload = JSON.parse(json)
    assert_operator json.bytesize, :<=, 65_535
    assert payload["response_truncated"]
    assert_operator payload["groups"].length, :<, 500
  end
end
