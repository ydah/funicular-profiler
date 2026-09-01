# Profiler protocol v1

Profiler gem version and protocol schema version are independent. A consumer must reject an unknown `schema_version` major value and ignore unknown fields within version 1.

## Availability and controls

Development browser builds expose `$__funicular_profiler__` only after explicit installation. The bridge may call only:

```text
snapshot_json(after_seq, limit)
summary_json
start!
stop!
clear!
recording?
```

The bridge must not accept an arbitrary Ruby method name. Server-side installs do not export the global.

## Snapshot

`snapshot_json(after_seq, limit)` clamps `limit` to `1..200`, targets 60 KiB, and returns at most 65,535 bytes so the C bridge retains space for a null terminator.

```json
{
  "schema_version": 1,
  "session_id": 1,
  "recording": true,
  "cursor": 0,
  "next_cursor": 2,
  "oldest_seq": 1,
  "newest_seq": 2,
  "cursor_gap": false,
  "has_more": false,
  "dropped_count": 0,
  "dropped_in_flight_count": 0,
  "truncated_attribute_count": 0,
  "dropped_attribute_count": 0,
  "invalid_numeric_count": 0,
  "adapter_error_count": 0,
  "corrupt_record_count": 0,
  "records": []
}
```

- `seq` is assigned in completion order.
- `next_cursor` is the last returned sequence, or the requested cursor for an empty page.
- A corrupt internal entry is omitted and treated as consumed, so `next_cursor` may advance past it; this prevents a polling client from retrying the same broken entry forever.
- `cursor_gap` means newer records were overwritten before the caller read them.
- `session_id` increments on `clear!`; consumers must then discard their cursor and local view.
- `response_truncated: true` means records were removed from the tail to meet the JSON byte limit.

Each record contains `schema_version`, `seq`, `kind`, `id`, `parent_id`, `name`, `started_at_us`, `duration_us`, `status`, and `attributes`. Times are monotonic microseconds relative to the runtime, not wall-clock timestamps. Status is `ok`, `error`, or `cancelled`.

## Summary

`summary_json` groups the retained records by instrumentation name and sanitized component class. Each group contains count, error count, empty-diff count, total/max duration, and p50/p95 duration. At most 500 groups are returned; excess cardinality is folded into `<other>`. JSON responses use the same 60 KiB target and set `response_truncated` if tail groups must be omitted.

## Failure response

```json
{
  "schema_version": 1,
  "error": "snapshot_failed",
  "message": "Profiler snapshot could not be generated"
}
```

Internal exception messages and backtraces are never returned as protocol failures.
