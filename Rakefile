# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "lib"
  task.libs << "minitest"
  task.test_files = FileList["minitest/**/*_test.rb"]
end

namespace :test do
  desc "Run profiler tests under Funicular's vendored PicoRuby runtime"
  task :pico do
    require "funicular/testing"

    result = Funicular::Testing.run!(
      app_root: __dir__,
      source_dir: File.join(__dir__, "mrblib"),
      test_glob: "test/**/*_test.rb",
      timeout_ms: 60_000
    )
    puts result.output unless result.output.empty?
    puts result.picotest_summary
    abort "PicoRuby profiler tests failed" unless result.success? && result.picotest_test_count.positive?
  end
end

task default: :test
