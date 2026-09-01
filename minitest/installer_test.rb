# frozen_string_literal: true

require_relative "test_helper"

class InstallerTest < Minitest::Test
  def test_explicit_idempotent_install_controls_and_uninstall
    Funicular::Profiler.install!(capacity: 100, max_in_flight: 16, enabled: true)
    assert Funicular::Profiler.recording?
    assert Funicular::Instrumentation.registered?(:profiler)
    assert_same Funicular::Profiler,
                Funicular::Profiler.install!(capacity: 100, max_in_flight: 16, enabled: true)
    assert_raises(Funicular::Profiler::AlreadyInstalledError) do
      Funicular::Profiler.install!(capacity: 101, max_in_flight: 16, enabled: true)
    end

    Funicular::Profiler.stop!
    refute Funicular::Profiler.recording?
    Funicular::Profiler.start!
    assert Funicular::Profiler.recording?
    Funicular::Profiler.uninstall!
    refute Funicular::Instrumentation.registered?(:profiler)
    refute Funicular::Profiler.recording?
    Funicular::Profiler.uninstall!
  end

  def test_server_does_not_export_global
    Funicular.server = true
    Funicular::Profiler.install!(capacity: 100, max_in_flight: 16, enabled: true)
    assert_nil $__funicular_profiler__
  end

  def test_development_browser_exports_global_and_records_by_default
    environment = Object.new
    environment.define_singleton_method(:development?) { true }
    Funicular.server = false
    Funicular.environment = environment
    Funicular::Profiler.install!(capacity: 100, max_in_flight: 16)

    assert_same Funicular::Profiler, $__funicular_profiler__
    assert Funicular::Profiler.recording?
  end

  def test_failed_registration_does_not_leave_partial_install
    Funicular::Instrumentation.register(:profiler, Object.new)
    assert_raises(ArgumentError) do
      Funicular::Profiler.install!(capacity: 100, max_in_flight: 16, enabled: true)
    end
    refute Funicular::Profiler.installed?
  end

  def test_real_funicular_instrumentation_contract
    Funicular::Profiler.install!(capacity: 100, max_in_flight: 16, enabled: true)
    parent = Funicular::Instrumentation.start("parent")
    Funicular::Instrumentation.with_span(parent) do
      Funicular::Instrumentation.event("child", nil, { "count" => 1 })
    end
    Funicular::Instrumentation.finish(parent)

    records = Funicular::Profiler.snapshot["records"]
    assert_equal %w[event span], records.map { |record| record["kind"] }
    assert_equal records[1]["id"], records[0]["parent_id"]
    assert_equal 0, Funicular::Instrumentation.diagnostics[0][:failures]
  end

  def test_another_adapter_failure_does_not_break_the_operation_or_profiler
    broken = Object.new
    broken.define_singleton_method(:start) { |_span, _parent| raise "broken" }
    Funicular::Instrumentation.reporter = ->(_message) {}
    Funicular::Instrumentation.register(:broken, broken)
    Funicular::Profiler.install!(capacity: 100, max_in_flight: 16, enabled: true)

    assert_equal 42, Funicular::Instrumentation.instrument("work") { 42 }
    assert_equal 1, Funicular::Instrumentation.diagnostics[0][:failures]
    assert_equal 1, Funicular::Profiler.snapshot["records"].length
  end
end
