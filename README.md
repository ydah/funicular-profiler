# funicular-profiler

`funicular-profiler` records Funicular instrumentation spans in a bounded, browser-local buffer for development tools. It has no network transport, persistence, OpenTelemetry dependency, or UI.

## Installation

Add the gem to the Funicular bundle. Loading it does not start recording.

```ruby
group :funicular do
  gem "funicular-profiler"
end
```

Install it explicitly from application startup code:

```ruby
Funicular::Profiler.install!(
  capacity: 2_000,
  max_in_flight: 256,
  enabled: Funicular.env.development?
)
```

The development repository pins an exact Funicular commit through `integration.lock.yml`; the gemspec deliberately contains no fork URL or branch.

## Control and snapshots

```ruby
Funicular::Profiler.start!
Funicular::Profiler.stop!
Funicular::Profiler.clear!
Funicular::Profiler.recording?

page = Funicular::Profiler.snapshot(after_seq: 0, limit: 200)
json = Funicular::Profiler.snapshot_json(0, 200)
summary = Funicular::Profiler.summary
Funicular::Profiler.uninstall!
```

`stop!` closes current spans as `cancelled`; `clear!` resets completed records and counters without changing the recording state. Reinstalling with different bounds requires `uninstall!` first.

The positional JSON API is intended for the allowlisted PicoRuby DevTools bridge. Responses never exceed 64 KiB. See [the protocol contract](docs/protocol.md).

## Data boundaries

The profiler accepts bounded scalar attributes only. It does not inspect arbitrary objects and automatically rejects sensitive keys. Built-in instrumentation must not collect:

- state, props, form values, DOM text, or event objects
- URL queries/fragments, request or response bodies, cookies, sessions, or credentials
- raw SQL, bind values, database keys, or Cable identifiers
- user or tenant identifiers

Error class and a bounded local error message may appear in local snapshots. The profiler performs no network requests and does not persist profiles.

## Development

```sh
bundle install
bundle exec rake test
bundle exec rake test:pico
script/verify_integration_pin
```

Benchmarks emit JSON so a local result can be kept as a machine-specific baseline and compared without making timing noise a CI failure:

```sh
bundle exec ruby benchmark/profile_buffer.rb > /tmp/profile-buffer-baseline.json
bundle exec ruby benchmark/profile_buffer.rb > /tmp/profile-buffer-current.json
bundle exec ruby benchmark/compare.rb /tmp/profile-buffer-baseline.json /tmp/profile-buffer-current.json
bundle exec ruby benchmark/compare.rb --self-test
```

Use `script/update_integration_pin <40-character-sha>` only in a dedicated dependency update change. Floating branch compatibility is isolated to the non-blocking CI job.
