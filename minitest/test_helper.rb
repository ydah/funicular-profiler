# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "funicular-profiler"

$__funicular_profiler__ = nil

class << Funicular
  attr_writer :server, :environment

  def server?
    @server != false
  end

  def env
    @environment
  end
end

FakeSpan = Struct.new(
  :id, :parent_id, :name, :started_at_us, :attributes, :ended_at_us, :status, :error,
  keyword_init: true
)
FakeEvent = Struct.new(:sequence, :name, :occurred_at_us, :attributes, :parent_id, keyword_init: true)

class Minitest::Test
  def setup
    Funicular::Profiler.uninstall!
    Funicular::Instrumentation.__reset
    Funicular.server = true
    Funicular.environment = nil
  end

  def span(id: 1, parent_id: nil, name: "work", started_at_us: 100, ended_at_us: 150,
           attributes: {}, status: :ok, error: nil)
    FakeSpan.new(
      id: id, parent_id: parent_id, name: name, started_at_us: started_at_us,
      attributes: attributes, ended_at_us: ended_at_us, status: status, error: error
    )
  end
end
