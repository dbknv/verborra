# Specification: Diagnostic Logging

**Feature Branch**: `007-diagnostic-logging`
**Created**: 2026-03-18
**Status**: Draft
**Description**: Structured logging system for all
application components with four modes (OFF / ERROR / INFO / DEBUG),
output to console and file, log rotation, and level configuration
in advanced settings. Logs are intended for centralized
collection and retrospective incident analysis.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Diagnosing audio device problems (Priority: P1)

A developer connects AirPods to a Mac and launches the application.
When switching between the built-in microphone and AirPods,
a problem occurs — recording does not start. The developer opens
Console.app (or the log file), filters by the application's subsystem,
and sees the full sequence of events: Bluetooth device detection,
audio profile switching (A2DP → HFP/SCO),
attempt to capture the audio stream, an error with description and context.

**Why P1**: without audio subsystem logging it is impossible
to diagnose the most frequent user problems —
a non-working microphone and device switching.

**Independent test**: connect/disconnect a Bluetooth audio device
and ensure that all events are displayed in the log with correct
timestamps, categories, and levels.

**Acceptance Scenarios**:

1. **Given** the application is running at INFO level,
   **When** the user connects AirPods,
   **Then** the log shows entries: device detection,
   its name, type, connection status.

2. **Given** the application is running at DEBUG level,
   **When** an audio device switch occurs,
   **Then** the log shows: audio stream parameters
   (sample rate, channels, bit depth, format),
   Bluetooth profile, input node configuration,
   device driver/firmware version (if available),
   list of all active streams.

3. **Given** the application is running at INFO level,
   **When** AirPods switch from A2DP profile
   to HFP/SCO to use the microphone,
   **Then** the log records: device name,
   old profile, new profile, switching result.

4. **Given** the application is running,
   **When** a Bluetooth device loses connection during recording,
   **Then** the log records an error with cause description,
   device name, and recording state at the moment of failure.

5. **Given** the application is running at DEBUG level,
   **When** recording starts with a Bluetooth microphone,
   **Then** the log shows: audio engine creation and startup,
   input node configuration, tap setup (format, buffer size),
   active audio stream parameters, audio format.

6. **Given** the application is recording audio,
   **When** the device sample rate changes at runtime
   (e.g. when switching Bluetooth profile),
   **Then** the log shows: old and new sample rate,
   tap recreation with the new format, result.

7. **Given** the application is running at INFO level,
   **When** the user selects an audio device from the list,
   **Then** the log shows: device name, ID, type,
   switching result (success/error).

---

### User Story 2 — Debugging API requests (Priority: P2)

The developer notices that transcription returns
an incorrect result. They switch the log level
to DEBUG in the application settings and repeat the recording.
The log shows: request sent to the OpenAI Whisper API
(URL, headers without API key, payload size),
received response (status, response body), execution time.
Requests to the Chat Completions API are logged similarly.

**Why P2**: API interaction is the second most frequent
source of problems after audio devices.

**Independent test**: perform a recording and transcription,
verify the presence of all API interaction stages in the log.

**Acceptance Scenarios**:

1. **Given** log level INFO,
   **When** a request to the Whisper API is performed,
   **Then** the log shows: URL, HTTP method, payload size,
   HTTP response status, request execution time.

2. **Given** log level DEBUG,
   **When** a request to the Chat Completions API is performed,
   **Then** the log additionally shows: request headers
   (without API key), request body (prompt, model parameters),
   response body.

3. **Given** the API returns an error (4xx / 5xx),
   **When** logging at any level,
   **Then** the error is recorded with HTTP status,
   response body, and call context.

---

### User Story 3 — Diagnosing permissions (Priority: P2)

A user complains that the application does not record sound.
The developer reviews the log and sees: microphone access
request was denied, Accessibility status — not granted,
re-check attempts and their results.

**Why P2**: permission problems are a frequent scenario
on macOS, especially after a system update.

**Independent test**: revoke microphone permission
in System Settings, start recording — verify
that the denial and context are recorded in the log.

**Acceptance Scenarios**:

1. **Given** the application is running,
   **When** microphone access is requested,
   **Then** the log shows: the fact of the request, the result (granted/denied),
   timestamp.

2. **Given** the application is running,
   **When** Accessibility status is checked,
   **Then** the log shows: check result,
   timestamp.

3. **Given** microphone permission was revoked,
   **When** the user tries to start recording,
   **Then** the log shows: error with description "microphone access
   denied", call context.

---

### User Story 4 — Tracking user actions (Priority: P3)

The developer wants to reproduce a bug described by a user.
The log shows the full action sequence: hotkey press,
prompt selection, recording start/end, language switch,
settings opening, parameter changes.

**Why P3**: user action tracing is useful
for reproducing complex scenarios, but less critical
than audio and API diagnostics.

**Independent test**: perform a typical usage
scenario and ensure that each action
is recorded in the log.

**Acceptance Scenarios**:

1. **Given** log level INFO,
   **When** the user presses a global hotkey,
   **Then** the log shows: "hotkey triggered" event,
   recording state before and after.

2. **Given** log level DEBUG,
   **When** the user changes settings,
   **Then** the log shows: name of the changed parameter,
   old and new value (except for API key).

---

### User Story 5 — Retrospective incident analysis (Priority: P2)

A user reports a problem: "recording broke off
in the middle." The developer obtains the log file, opens it,
and uses the session ID to find all events of that run.
They see the full chain: application start → device selection
→ recording start → Bluetooth profile switch →
tap error → ERROR with failure description, state at the moment
of error and steps that led to it. From a single log file
the full picture of the incident can be reconstructed.

**Why P2**: centralized log collection from multiple
devices is the main support scenario; without session ID
and full error context, analysis is impossible.

**Independent test**: simulate an error (e.g.,
disconnect Bluetooth during recording), collect the log file,
and reconstruct the full event chain from it.

**Acceptance Scenarios**:

1. **Given** the application is running and recording,
   **When** a failure occurs (loss of Bluetooth device),
   **Then** the ERROR log message contains: what broke,
   the chain of preceding steps, state at the moment of error
   (device name, recording status, duration),
   error code/type.

2. **Given** the developer received a log file from a user,
   **When** they filter by session ID,
   **Then** they see all events of a single application run
   in chronological order from start to error.

3. **Given** the log file contains an ERROR message,
   **When** the developer reads only this message,
   **Then** they can understand the failure cause without additional
   information (the context is self-sufficient).

4. **Given** multiple log files from different users,
   **When** the developer analyzes them centrally,
   **Then** the session ID allows separating events
   of different runs even in a merged stream.

---

### User Story 6 — Managing logging and log files (Priority: P3)

The user (or developer) opens advanced
application settings and switches the log level
from INFO to DEBUG for detailed diagnostics. Logs are written
to a file, files are rotated every hour, old files
are deleted after 24 hours.

**Why P3**: logging management is an infrastructure
function necessary for the other scenarios to work.

**Independent test**: switch the level in settings,
ensure that logs are written with the new level;
verify that files are rotated and deleted on schedule.

**Acceptance Scenarios**:

1. **Given** the default level is INFO,
   **When** the user opens advanced settings,
   **Then** the current log level is displayed
   with the ability to select: OFF, ERROR, INFO, DEBUG.

2. **Given** the user switched the level to DEBUG,
   **When** the application continues to run,
   **Then** DEBUG messages start being recorded immediately
   without restarting the application.

3. **Given** the application has been running for more than 1 hour,
   **When** the rotation moment arrives,
   **Then** the current log file is closed, a new one is created,
   files older than 24 hours are deleted automatically.

4. **Given** the application writes logs to a file,
   **When** file size or their count is checked,
   **Then** logs are stored for no more than 24 hours (by default).

---

### Edge Cases

- What happens if the disk is full and the log file
  cannot be created? Logging switches
  to console only, the error is recorded.
- What if a Bluetooth device connects/disconnects
  multiple times in a short period? Each event
  is logged, but no more often than once per 100 ms per-device
  (throttling is applied to each device independently).
- How is log level switching handled
  during active recording? The level is applied immediately,
  the current recording is not interrupted. Exception: switching
  to OFF is deferred until the current recording operation completes
  (so as not to lose context in case of a possible error).
- What if an API key accidentally gets into the log? All
  sensitive data MUST be masked.
- What if the device's audio stream format does not match
  the format expected by the audio engine? The mismatch
  MUST be logged with both formats and the result
  of automatic conversion (if applicable).
- What if the audio engine cannot start (e.g.,
  device is busy with another application)? The error MUST
  be logged with cause description and device name.
- What happens on application crash?
  ERROR messages are guaranteed to be written to disk (flush
  on each ERROR). INFO/DEBUG messages from the last
  5 seconds may be lost. os_log sink is not affected
  (managed by the system).

## Clarifications

### Session 2026-03-19

- Q: Log file format? → A: JSON Lines (JSONL) — each line = JSON object
- Q: Depth of step chain in ERROR? → A: 20 most recent actions
- Q: Logging modes available to the user? → A: OFF / ERROR / INFO / DEBUG (4 modes)
- Q: How does the user pass logs to the developer? → A: Link to the logs directory in Finder next to the mode setting
- Q: OFF behavior during active recording? → A: OFF is deferred until the current recording operation completes
- Q: Log file size limit? → A: 50 MB — rotation on reaching size OR on time (whichever comes first)
- Q: Console output mechanism? → A: Two sinks: os_log (Console.app + Xcode) + JSONL file
- Q: JSONL write reliability on crash? → A: Flush on every ERROR + periodic flush (every 5 sec) for other levels
- Q: os_log behavior in OFF mode? → A: OFF disables both sinks completely (os_log + JSONL)
- Q: Bluetooth event throttling scope? → A: Per-device — 100 ms for each device independently
- Q: Scope of "current operation" for the 20-step chain in ERROR? → A: Per-flow — from the initiating user action (hotkey press, recording start) to the error
- Q: Logging concurrency model? → A: Asynchronous serial queue — call does not block, write happens on a background thread

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support four logging
  modes: OFF (disabled), ERROR (errors only),
  INFO (errors + key events), DEBUG (everything).
- **FR-002**: The INFO level MUST record key
  lifecycle events: application start/stop,
  recording start/end, device selection,
  API call result, user actions.
- **FR-003**: The DEBUG level MUST additionally record:
  audio stream parameters (sample rate, channels, bit depth,
  buffer size, format), audio engine configuration
  (graph topology, connected nodes), payload
  of API requests and responses (first 500 characters;
  API keys are masked, request/response contents
  are shown for diagnostics), intermediate
  states, variable values at key points,
  driver/firmware versions of devices.
- **FR-004**: Logs MUST be output through two independent sinks:
  (1) `os_log` (Apple Unified Logging) — displayed in Console.app
  and Xcode Console with filtering by subsystem/category;
  (2) JSONL file — for transfer and centralized analysis.
- **FR-005**: Log files MUST be rotated every hour
  OR when reaching a size of 50 MB (whichever comes first).
- **FR-006**: Log files older than 24 hours MUST
  be deleted automatically.
- **FR-007**: Default log level — INFO.
- **FR-008**: The user MUST be able to
  change the log level in the advanced application
  settings without restart.
- **FR-020**: Next to the log mode selection in the settings,
  there MUST be a (clickable) link opening the directory
  with log files in Finder. The user finds the needed
  file independently and passes it to the developer.
- **FR-009**: Each log message MUST contain:
  timestamp (ISO 8601 with milliseconds), level,
  category (module/service), session ID (unique
  application session identifier from start to end),
  message text. The session ID MUST allow
  linking all events of a single application run
  during centralized log collection.
- **FR-010**: The ERROR level records all errors and failures.
  ERROR-level messages MUST be logged at levels
  ERROR, INFO, and DEBUG. In OFF mode logging is fully
  disabled (including errors) — both sinks (os_log and JSONL)
  stop writing.
  Each ERROR message MUST contain:
  - Error description (what exactly broke).
  - The chain of steps preceding the error
    (last 20 actions in the current flow — from the initiating
    user action to the error).
  - State at the moment of the error: active device,
    recording status, current operation.
  - Method name and call parameters.
  - Error code or exception type (if applicable).
  From a single ERROR message it MUST be possible
  to understand the cause of the failure without access to the user's machine.
- **FR-011**: API keys MUST NOT be written to the log
  in plain form — they MUST be masked (`sk-...XXXX`).
  Audio buffer contents MUST NOT be logged
  (only metadata: samples, format).
  Recognized text and bodies of API requests/responses
  MAY be logged in DEBUG mode (first 500 characters)
  for diagnostic purposes.
- **FR-012**: The following event categories MUST be logged:
  - Bluetooth / AirPods: detection, connection, disconnection,
    profile change (A2DP ↔ HFP/SCO), connection loss,
    connection quality on profile change.
  - Audio devices: enumeration of available devices
    (name, ID, type, driver/firmware version if available),
    start of use, switching between devices,
    active stream parameters (sample rate, channels,
    bit depth, format).
  - Audio engine: creation, start, stop,
    reset, initialization errors; in DEBUG — full
    configuration (graph topology, connected nodes).
  - Audio tap: tap setup on input node, tap removal,
    tap format (sample rate, channels, buffer size),
    format change at runtime, tap errors.
  - Audio streams: enumeration of active streams,
    each stream format, sample rate change
    at runtime (e.g. when switching device),
    format mismatch between device and engine.
  - Permissions: microphone request, result, Accessibility
    check, status change.
  - API requests: URL, method, payload size, response status,
    execution time; in DEBUG — full payload
    (headers without API key, request body, response body).
  - User actions: hotkey press, UI button presses,
    settings change (old → new value,
    except API key), prompt/language selection.
  - System calls: text insertion via clipboard,
    keyboard event simulation, desktop interaction,
    autostart management.
  - Application lifecycle: launch, termination,
    transition to background, return to active state.
- **FR-013**: Each module/service MUST use
  a unique logging category for filtering.
- **FR-014**: Log file retention setting (24 hours
  by default, allowed range: 1–168 hours)
  is configured in advanced settings.
- **FR-015**: Log files MUST be located in the standard
  application data directory (Application Support).
- **FR-019**: Log file format — JSON Lines (JSONL):
  each line of the file MUST be a valid JSON object
  with fields from FR-009. The format provides machine parsing
  during centralized log collection. Console output
  MAY use a human-readable format.
- **FR-016**: In log files API keys MUST be
  masked (e.g., `sk-...XXXX`). Recognized text
  and payload of API requests/responses are logged in DEBUG
  (first 500 characters) without masking for diagnostics.
- **FR-021**: The JSONL file MUST force flush the buffer
  on every ERROR-level message. For other
  levels (INFO, DEBUG) the buffer MUST be flushed
  periodically — every 5 seconds. This ensures
  preservation of ERROR messages on application crash
  with minimal impact on performance.

- **FR-022**: The logging system MUST use
  an asynchronous serial queue for writing. The logging call
  MUST NOT block the calling thread (critical for
  real-time audio callbacks). Both sinks (os_log and JSONL)
  MUST be processed on a background thread. Exception:
  flush on ERROR may briefly block the queue,
  but not the calling thread.

- **FR-017**: (merged with FR-009 — session ID defined there).
- **FR-018**: Timestamp format — ISO 8601 with milliseconds
  and time zone (e.g., `2026-03-19T14:30:05.123+03:00`).
  A unified format MUST ensure correct sorting
  of events when merging logs from different sources.

### Key Entities

- **LogEntry**: a single log record — timestamp
  (ISO 8601 with ms), level (ERROR / INFO / DEBUG),
  session ID, category, message, optional context
  (metadata for ERROR: step chain, state, error code).
- **LogLevel**: logging mode — OFF, ERROR, INFO, DEBUG.
  OFF — logging is fully disabled.
  ERROR — errors only. INFO — errors + key events.
  DEBUG — everything (DEBUG + INFO + ERROR).
- **LogCategory**: module category — audio, bluetooth,
  permissions, api, userAction, lifecycle, settings,
  engine, tap, stream, system.
- **LogFile**: log file — path, creation time,
  last write time, size.
- **SessionID**: unique application run
  identifier, assigned at startup, identical
  for all records of one session.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When a Bluetooth device is connected/disconnected,
  corresponding events appear in the log within 1 second.
- **SC-002**: Each API request is recorded in the log
  with all mandatory fields (URL, method, status, time).
- **SC-003**: Switching the log level in settings
  takes effect without restarting the application — within
  1 second after the change.
- **SC-004**: Log files are rotated every hour;
  files older than 24 hours are absent from the logs directory.
- **SC-005**: No log message contains an API key
  or audio buffer contents in plain form.
- **SC-006**: Logging does not increase the time from hotkey press
  to recording readiness by more than 10 ms
  (does not violate the 300 ms requirement from the Constitution).
- **SC-007**: 100% of application services are integrated
  with the logging system and use unique categories.
- **SC-008**: The developer can filter logs
  by a specific module (category) and see only
  its events.
- **SC-009**: Each ERROR message contains enough
  context to diagnose the cause of the failure without access
  to the user's machine (description, steps, state).
- **SC-010**: By session ID, all events
  of a single application run can be extracted from a merged log stream
  of multiple devices.
- **SC-011**: Timestamps in all log messages
  contain milliseconds and time zone, ensuring
  correct chronological sorting.
