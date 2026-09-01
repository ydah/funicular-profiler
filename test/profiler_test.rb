class ProfilerPicoTest < Picotest::Test
  class Span
    attr_reader :id, :parent_id, :name, :started_at_us, :attributes, :ended_at_us, :status, :error

    def initialize(id, parent_id, name, started_at_us, attributes, ended_at_us, status, error)
      @id = id
      @parent_id = parent_id
      @name = name
      @started_at_us = started_at_us
      @attributes = attributes
      @ended_at_us = ended_at_us
      @status = status
      @error = error
    end
  end

  class Event
    attr_reader :sequence, :name, :occurred_at_us, :attributes, :parent_id

    def initialize(sequence, name, occurred_at_us, attributes, parent_id)
      @sequence = sequence
      @name = name
      @occurred_at_us = occurred_at_us
      @attributes = attributes
      @parent_id = parent_id
    end
  end

  def setup
    Funicular::Profiler.uninstall!
    Funicular::Instrumentation.__reset
  end

  def teardown
    Funicular::Profiler.uninstall!
    Funicular::Instrumentation.__reset
  end

  def test_real_funicular_instrumentation_contract
    Funicular::Profiler.install!(capacity: 100, max_in_flight: 16, enabled: true)
    assert_equal(Funicular::Profiler, $__funicular_profiler__)
    parent = Funicular::Instrumentation.start("parent")
    Funicular::Instrumentation.with_span(parent) do
      Funicular::Instrumentation.event("child", nil, { "count" => 1 })
    end
    Funicular::Instrumentation.finish(parent)

    records = Funicular::Profiler.snapshot["records"]
    assert_equal(2, records.length)
    assert_equal("event", records[0]["kind"])
    assert_equal(records[1]["id"], records[0]["parent_id"])
    assert_equal(0, Funicular::Instrumentation.diagnostics[0][:failures])
  end

  def test_bounded_recording_and_snapshot
    adapter = Funicular::Profiler::Adapter.new(capacity: 100, max_in_flight: 16)
    adapter.start_recording!
    span = Span.new(1, nil, "funicular.component.render", 100, {}, 175, :ok, nil)
    state = adapter.start(span, nil)
    adapter.finish(state, span)
    adapter.event(Event.new(1, "rendered", 180, { "count" => 1 }, 1))

    snapshot = adapter.snapshot(after_seq: 0, limit: 200)
    assert_equal(1, snapshot["schema_version"])
    assert_equal(2, snapshot["records"].length)
    assert_equal("s-1", snapshot["records"][0]["id"])
    assert_equal("s-1", snapshot["records"][1]["parent_id"])
    assert_equal(true, adapter.snapshot_json(0, 200).bytesize <= 65_535)
  end

  def test_wrap_and_sanitizer_bounds
    buffer = Funicular::Profiler::Buffer.new(100)
    103.times do |index|
      buffer.insert(Funicular::Profiler::Record.new(
        kind: "event", id: "e-#{index}", parent_id: nil, name: "event",
        started_at_us: index, duration_us: 0, status: "ok", attributes: {}
      ))
    end
    assert_equal(3, buffer.dropped_count)
    assert_equal(4, buffer.oldest_seq)
    assert_equal(true, buffer.page(0, 200)[:cursor_gap])

    sanitizer = Funicular::Profiler::Sanitizer.new
    attributes = sanitizer.attributes({ "token_count" => 1, "token" => "secret", "value" => "a" * 300 })
    assert_equal(1, attributes["token_count"])
    assert_equal(false, attributes.key?("token"))
    assert_equal(true, attributes["value"].bytesize <= 256)
  end
end
