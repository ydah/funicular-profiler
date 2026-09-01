# frozen_string_literal: true

require_relative "test_helper"

class BufferTest < Minitest::Test
  def record(id)
    Funicular::Profiler::Record.new(
      kind: "span", id: "s-#{id}", parent_id: nil, name: "work",
      started_at_us: id, duration_us: 1, status: "ok", attributes: {}
    )
  end

  def test_capacity_and_record_validation
    assert_raises(ArgumentError) { Funicular::Profiler::Buffer.new(99) }
    assert_raises(ArgumentError) { Funicular::Profiler::Buffer.new(20_001) }
    assert_raises(ArgumentError) do
      Funicular::Profiler::Record.new(
        kind: "span", id: "s-1", parent_id: nil, name: "work",
        started_at_us: 0, duration_us: 1, status: "unknown", attributes: {}
      )
    end
    assert_equal 0, Funicular::Profiler::Record.new(
      kind: "event", id: "e-1", parent_id: nil, name: "event",
      started_at_us: 0, duration_us: -1, status: "ok", attributes: {}
    ).duration_us
  end

  def test_wrap_paging_gap_and_clear
    buffer = Funicular::Profiler::Buffer.new(100)
    203.times { |index| buffer.insert(record(index)) }

    assert_equal 100, buffer.size
    assert_equal 103, buffer.dropped_count
    assert_equal 104, buffer.oldest_seq
    assert_equal 203, buffer.newest_seq

    first = buffer.page(0, 20)
    assert first[:cursor_gap]
    assert first[:has_more]
    assert_equal (104..123).to_a, first[:records].map(&:seq)
    second = buffer.page(first[:next_cursor], 500)
    refute second[:has_more]
    assert_equal (124..203).to_a, second[:records].map(&:seq)

    session = buffer.session_id
    buffer.clear!
    assert_equal session + 1, buffer.session_id
    assert_nil buffer.oldest_seq
    assert_equal 0, buffer.dropped_count
    assert_equal 1, buffer.insert(record(999)).seq
  end

  def test_record_does_not_retain_mutable_strings_or_arrays
    name = +"work"
    value = +"value"
    list = [value]
    item = Funicular::Profiler::Record.new(
      kind: "span", id: "s-1", parent_id: nil, name: name,
      started_at_us: 0, duration_us: 1, status: "ok", attributes: { "key" => list }
    )
    name << " changed"
    value << " changed"
    list << "extra"

    assert_equal "work", item.name
    assert_equal ["value"], item.attributes["key"]
    assert item.attributes.frozen?
    assert item.attributes["key"].frozen?
  end
end
