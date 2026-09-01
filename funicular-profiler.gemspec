# frozen_string_literal: true

require_relative "lib/funicular/profiler/version"

Gem::Specification.new do |spec|
  spec.name = "funicular-profiler"
  spec.version = Funicular::Profiler::VERSION
  spec.authors = ["Yudai Takada"]
  spec.summary = "Bounded local profiler for Funicular applications"
  spec.description = "Records Funicular instrumentation spans locally for development tooling."
  spec.homepage = "https://github.com/ydah/funicular-profiler"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir[
    "LICENSE.txt", "README.md", "mrbgem.rake",
    "docs/**/*.md", "lib/**/*.rb", "mrblib/**/*.rb", "sig/**/*.rbs"
  ]
  spec.require_paths = ["lib"]
  spec.metadata["source_code_uri"] = spec.homepage

  spec.add_dependency "funicular"
end
