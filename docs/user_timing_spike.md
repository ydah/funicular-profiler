# User Timing spike

Decision: **No-Go** for the optional User Timing adapter. Do not implement PR 4 against the current bridge.

## Evidence

The probe used Funicular `8d013fcb501b3db038dc10b9077d47f667ccd1bf` and its vendored PicoRuby `0277264982a9262e1f66f6d215aaf85db7a40cef` under Node 24.14.1. A PicoRuby loop made 100,000 cached `performance.now()` calls. Subtracting an empty Ruby loop measured about 0.37 microseconds per synchronous Ruby-to-JavaScript call on this machine.

This is bridge evidence, not a browser performance budget: Node, JavaScriptCore/V8 differences, WASM build flags, GC, and DevTools recording can materially change the result. A browser benchmark is still required before accepting any overhead.

## Calls and cleanup

The mark-based direct API requires separate `performance.mark`, `performance.measure`, `performance.clearMarks`, and `performance.clearMeasures` operations. A span therefore adds multiple Ruby-to-JavaScript calls per completed record. This fails PR 4's explicit one-call condition with the current bridge.

User Timing Level 3 can create a measure from numeric `start` and `duration` without marks. With today's generic bridge, however, creating the JavaScript options object, setting its properties, calling `measure`, and clearing the measure still crosses the bridge multiple times. A dedicated preloaded JavaScript helper could combine those operations into one Ruby call, but no such helper or browser lifecycle test exists in this repository; adding it is adapter implementation, not evidence from this spike.

Marks and measures are independent entry types. Cleanup must clear every type created, preferably by its low-cardinality name. The [User Timing specification](https://www.w3.org/TR/user-timing/) says clearing removes entries from the performance entry buffer. The [Performance Timeline specification](https://www.w3.org/TR/performance-timeline/) queues registered observers separately, so a helper might measure and immediately clear without starving an already registered observer; a later `getEntries()` consumer would not see that entry. The intended Chrome DevTools behavior still needs browser E2E proof before relying on this scheme.

## Entry growth

A Node native User Timing probe created 1,000 marks and 1,000 measures. `performance.getEntries()` retained 2,000 entries until both clear methods ran, after which it retained zero. Without deterministic cleanup, entry count grows with recorded spans even though the profiler's Ruby ring buffer is bounded.

## Node fake

The Funicular Node runner's jsdom `performance` object provides `now()` but not `mark`, `measure`, or the clear methods. A small object installed on `globalThis` was callable from PicoRuby and verified 1,000 retained fake measures followed by zero after cleanup. This is sufficient for adapter call-count, no-bridge, and failure-isolation tests, but it does not validate native PerformanceEntry or browser DevTools behavior.

## Revisit gate

Revisit by prototyping the one-call JavaScript helper and proving that Chrome DevTools captures its measure after immediate cleanup. Then measure the actual PicoRuby.wasm browser build with and without DevTools open. Until both are demonstrated, the bounded JSON profiler remains the only implementation.
