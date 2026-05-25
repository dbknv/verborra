# Research: Diagnostic Logging

**Feature**: 007-diagnostic-logging
**Date**: 2026-03-19

## Decision 1: Logging architecture (Dual-Sink)

**Decision**: DiagnosticLogger facade dispatching to two independent sinks:
os.Logger (Unified Logging) and JSONL file via async serial queue.

**Rationale**:
- os.Logger cannot be intercepted or extended — it writes directly to the system log
  through a kernel-level transport. The only way is to call both sinks independently.
- The facade encapsulates both calls, checks LogLevel and masks data.
- Each service gets its own facade instance with a unique category.

**Alternatives considered**:
- ~~SwiftLog (apple/swift-log)~~: an abstraction over backends, but adds
  a dependency and does not give direct control over the JSONL format and breadcrumbs.
  The Constitution requires minimum dependencies.
- ~~CocoaLumberjack~~: Objective-C legacy, heavy, violates Principle 2 (Swift-first).
- ~~OSLogStore API~~: Allows reading system logs, but is not suitable for
  writing to a file — reading logs requires an entitlement and is restricted by the sandbox.

## Decision 2: File log format

**Decision**: JSON Lines (JSONL) — each line = valid JSON object.

**Rationale**:
- Machine parsing for centralized collection (jq, Python, ELK stack).
- Crash-safe: at most one incomplete line is lost.
- Append-only writes — no need to read/parse the file to append.
- Lexicographic sort by timestamp for log merging.

**Alternatives considered**:
- ~~Plain text~~: poorly parsed automatically, no structure for metadata.
- ~~SQLite~~: excessive complexity, works poorly with the append-only scenario,
  problems on crash (WAL mode helps, but complicates things).
- ~~Protobuf / binary~~: more compact, but unreadable by humans; complicates debugging.

## Decision 3: File writing mechanism

**Decision**: FileHandle in append mode + DispatchQueue (serial, qos: .utility).

**Rationale**:
- FileHandle.write(_:) — a simple API for append; seekToEndOfFile() on open.
- synchronizeFile() for flush (ERROR: immediately, others: every 5 sec).
- Serial queue provides thread safety without locks for file operations.
- DispatchSourceTimer on the same queue for periodic flush.
- qos: .utility — does not block UI, but is high enough priority for timely writes.

**Alternatives considered**:
- ~~OutputStream~~: more complex lifecycle (open/close/hasSpaceAvailable),
  designed for network protocols.
- ~~fwrite/fputs (C interop)~~: faster, but FileHandle is fast enough
  for the expected volumes (~100-1000 records/min).
- ~~Actor-based~~: Swift Concurrency actor instead of DispatchQueue.
  Problem: actor uses the cooperative thread pool, which may be
  overloaded by other tasks. DispatchQueue provides deterministic serial execution.

## Decision 4: Breadcrumb trail for ERROR

**Decision**: Per-flow RingBuffer (capacity: 20) with FlowTracker.

**Rationale**:
- Flow = from the initiating action (hotkey) to completion (text paste or error).
- UUID for each flow; breadcrumbs are tied to the flow ID.
- RingBuffer O(1) append, O(n) drain — optimal for capacity 20.
- NSLock for thread safety (low contention — breadcrumb writes are fast).
- On ERROR: drain all breadcrumbs → include in the JSONL record → remove the flow.

**Alternatives considered**:
- ~~Global ring buffer~~: loses context during parallel operations
  (unlikely in the current application, but architecturally incorrect).
- ~~Per-category buffer~~: does not reflect the user flow
  (audio + API + paste — different categories in one flow).
- ~~os_activity / os_signpost~~: Apple API for tracing, but does not allow
  including data in JSONL; intended for Instruments.

## Decision 5: Log rotation and cleanup

**Decision**: Hourly rotation + 50 MB limit; cleanup of files older than 24 hours.

**Rationale**:
- File name: `verborra-yyyy-MM-dd'T'HH.jsonl` — sorts lexicographically.
- Rotation check: on every write (comparing the current hour + file size).
- Size is tracked in-memory (counter), not via stat() on every write.
- Cleanup at startup + every hour (by timer or on rotation).
- Disk full: switch to os_log only; attempt cleanup to free space.

**Alternatives considered**:
- ~~Daily rotation~~: files are too large for DEBUG mode.
- ~~By record count~~: unpredictable file size.
- ~~External logrotate~~: not available in macOS sandbox; not portable.

## Decision 6: Sensitive data masking

**Decision**: Two-level masking.

**Rationale**:
- **os_log**: `\(value, privacy: .private)` — built-in Apple mechanism.
  In release builds shows `<private>` in Console.app.
  In debug builds with debugger — shows the full value.
- **JSONL**: `SensitiveMasker` — manual masking before serialization:
  - API key: `sk-...XXXX` (prefix 3 + suffix 4)
  - Recognized text: `[transcription:Nchars]` (length only)
  - Audio buffer: not logged (only metadata)
- Masking is applied in DiagnosticLogger BEFORE passing to JSONLFileWriter.

**Alternatives considered**:
- ~~Log encryption~~: excessive complexity; logs are intended for reading
  by the developer, not for transfer over open channels.
- ~~Full exclusion of metadata~~: loss of diagnostic value;
  masking is a compromise between security and utility.

## Decision 7: Integration with existing services

**Decision**: Minimally invasive integration via a static factory method.

**Rationale**:
- `DiagnosticLogger.logger(for: .audio)` — creates a logger for a category.
- Services do NOT receive the logger via DI (constructor), so as not to change
  signatures and protocols of existing services.
- Each service stores the logger as a `private let log` property.
- log.info/log.debug/log.error calls are added at key points.

**Alternatives considered**:
- ~~DI through constructor~~: would require changing all protocols and creation points
  (~16 services); a disproportionate amount of changes for logging.
- ~~Global singleton~~: works, but does not allow filtering by category
  without passing the category in every call.
- ~~Property wrapper (@Logged)~~: interesting for automatic logging of
  property changes, but too "magical"; not suitable for method calls.

## Decision 8: UI for configuring the log level

**Decision**: Extending AdvancedSettingsTab.swift — Picker for LogLevel
and a "Show logs in Finder" button.

**Rationale**:
- AdvancedSettingsTab already exists and contains minimal UI (reset onboarding).
- Picker with four options (OFF/ERROR/INFO/DEBUG) — a standard macOS control.
- NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath:) — opens
  the logs directory in Finder.
- The value is stored via @AppStorage("logLevel") in AppSettings.

**Alternatives considered**:
- ~~Separate tab~~: excessive for two controls.
- ~~Menu Bar item~~: does not match the current settings architecture.
- ~~Launch argument / environment variable~~: not user-friendly.
