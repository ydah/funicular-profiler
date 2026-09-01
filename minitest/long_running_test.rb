# frozen_string_literal: true

require_relative "test_helper"

class LongRunningTest < Minitest::Test
  class CorruptRecord
    attr_reader :seq

    def with_seq(seq)
      @seq = seq
      self
    end

    def to_h
      raise "corrupt"
    end
  end

  def test_one_hundred_thousand_records_remain_bounded
    buffer = Funicular::Profiler::Buffer.new(100)
    record = Funicular::Profiler::Record.new(
      kind: "event", id: "e", parent_id: nil, name: "event",
      started_at_us: 0, duration_us: 0, status: "ok", attributes: {}
    )
    100_000.times { buffer.insert(record) }

    assert_equal 100, buffer.size
    assert_equal 99_900, buffer.dropped_count
    assert_equal 99_901, buffer.oldest_seq
    assert_equal 100_000, buffer.newest_seq
  end

  def test_corrupt_record_does_not_destroy_snapshot
    adapter = Funicular::Profiler::Adapter.new(capacity: 100)
    adapter.buffer.insert(CorruptRecord.new)
    payload = adapter.snapshot

    assert_empty payload["records"]
    assert_equal 1, payload["corrupt_record_count"]
    assert_equal 1, payload["next_cursor"]
    assert_empty adapter.snapshot(after_seq: payload["next_cursor"])["records"]
    assert_equal 1, adapter.corrupt_record_count
  end
end
