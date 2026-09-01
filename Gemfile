# frozen_string_literal: true

require "yaml"

source "https://rubygems.org"

lock = YAML.safe_load_file(File.expand_path("integration.lock.yml", __dir__))
funicular = lock.fetch("dependencies").fetch("funicular")
repository = ENV.fetch("FUNICULAR_REPOSITORY", funicular.fetch("repository"))
revision = ENV.fetch("FUNICULAR_REF", funicular.fetch("revision"))

unless ENV["ALLOW_FLOATING_FUNICULAR"] == "1" || revision.match?(/\A[0-9a-f]{40}\z/)
  abort "FUNICULAR_REF must be a full 40-character commit SHA"
end

gem "funicular", git: repository, ref: revision, group: :funicular
gem "funicular-profiler", path: "."
