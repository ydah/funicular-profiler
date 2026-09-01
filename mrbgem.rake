MRuby::Gem::Specification.new("funicular-profiler") do |spec|
  spec.license = "MIT"
  spec.author = "Yudai Takada"
  spec.summary = "Bounded local profiler for Funicular applications"
  spec.add_dependency "picoruby-funicular"
  spec.add_dependency "picoruby-json"
end
