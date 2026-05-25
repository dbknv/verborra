<!--
  Sync Impact Report
  ==================
  Version change: 1.3.0 → 1.3.1 (exception for debug WAV recording)
  Modified principles:
    - Principle 4: added exception — audio MAY be saved
      to disk in WAV format for debugging purposes, if the user
      has explicitly enabled the option in Advanced Settings (off by default)
  Added sections: N/A
  Removed sections: N/A
  Templates requiring updates:
    ✅ plan-template.md — compatible
    ✅ spec-template.md — compatible
    ✅ tasks-template.md — compatible
  Follow-up TODOs: N/A
-->

# Project Constitution: Speech-to-Text for macOS

**Version**: 1.3.1
**Ratification date**: 2026-03-04
**Last modified**: 2026-03-20

## Preamble

This document defines the immutable principles, technical stack,
and constraints for the **Speech-to-Text** project — a desktop
macOS application that allows the user to activate voice
input via a global hotkey in any system text field and receive
formatted text as output. Speech recognition is performed
through the OpenAI Whisper API (ChatGPT API — voice-to-text),
text post-processing — through the OpenAI Chat Completions API.

All architecture and implementation decisions MUST conform to
the principles set out below. Deviations are permitted ONLY through
the amendment procedure (see the "Governance" section).

---

## Principle 1: Native macOS experience

The application MUST feel like a native part of macOS.

- The UI MUST use exclusively SwiftUI
  and native macOS components (NSPanel, NSWindow).
- The minimum supported version is macOS 15 (Sequoia).
  The application MUST support macOS 15, 26, and higher.
- The global hotkey MUST work in any application
  via the Accessibility API / CGEvent.
- Text insertion into the active field MUST use
  system mechanisms (NSPasteboard + CGEvent simulation
  of Cmd+V or the Accessibility API).
- The application MUST follow Human Interface Guidelines
  from Apple for macOS.
- The recording window MUST be a compact overlay panel
  (NSPanel) that does not steal focus from the target application.

**Rationale**: the user expects seamless integration
with the system; web technologies (Electron, Tauri) are prohibited.

---

## Principle 2: Swift-first development

All project code MUST be written in Swift.

- Minimum Swift version: 5.9 (or higher, if required
  to support the target macOS versions).
- Dependency management — Swift Package Manager (SPM).
- Architectural pattern — MVVM using
  `@Observable` (Observation framework) for macOS 15+.
- Network requests MUST use `URLSession`
  and Swift Concurrency (`async`/`await`).
- Objective-C is allowed ONLY for interacting
  with system APIs that have no Swift wrappers (for example,
  CGEvent, Accessibility API).
- Third-party dependencies MUST be minimal;
  each dependency MUST be justified
  in `research.md` of the corresponding feature.

**Rationale**: a single language reduces cognitive load
and simplifies maintenance; Apple promotes Swift as the primary
language for the platform.

---

## Principle 3: Minimalism and simplicity

The application MUST solve one task and solve it excellently.

- The interface MUST contain a minimum of elements: the recording
  window, status indicator, settings (hotkey, API key,
  language).
- The application MUST live in the Menu Bar (LSUIElement = YES),
  without an icon in the Dock.
- The time from pressing the hotkey to readiness for recording
  MUST NOT exceed 300 ms.
- The time from the end of recording to receiving the text depends
  on the API, but the UI MUST show progress (animation).
- Configuration MUST be stored via `UserDefaults`
  or `@AppStorage`; using external DBs is PROHIBITED.
- The OpenAI API key MUST be stored in the macOS Keychain.

**Rationale**: simplicity is the key to reliability and usability;
feature creep leads to loss of focus.

---

## Principle 4: Security and privacy

Audio data and API keys MUST be handled with maximum
protection.

- The audio recording MUST be transmitted directly to the OpenAI API
  and MUST NOT be saved to disk (in-memory buffer only).
  **Exception**: for debugging purposes, audio MAY be saved
  to disk in WAV format, if the user has explicitly enabled
  this option in Advanced Settings.
  By default, saving MUST be disabled.
- The API key MUST be stored in the macOS Keychain;
  storing it in UserDefaults, plist, or plain text is PROHIBITED.
- The application MUST correctly handle revocation
  of permissions (microphone, Accessibility) and inform
  the user.
- Network requests MUST use HTTPS (TLS 1.2+).
- The application MUST NOT collect telemetry
  or analytics without the user's explicit consent.
- App Sandbox MUST be enabled with the minimum
  necessary entitlements.

**Rationale**: the application has access to the microphone
and system input — user trust is critical.

---

## Principle 5: Code quality and testing

The code MUST be testable and maintainable.

- Business logic MUST be covered by unit tests
  (XCTest / Swift Testing).
- Network interaction MUST be abstracted
  through protocols to enable mocking.
- UI tests are NOT REQUIRED, but RECOMMENDED
  for critical user scenarios.
- Every PR MUST pass linting (SwiftLint)
  and build without warnings.
- Code MUST follow the Swift API Design Guidelines.
- API errors MUST be handled gracefully
  with clear messages for the user.

**Rationale**: a desktop application is hard to update
as quickly as the web — quality is critical from the first release.

---

## Principle 6: Logging and observability

The application MUST provide detailed diagnostic
logging for debugging all aspects of operation.

### Levels and output

- Four logging modes are supported:
  **OFF**, **ERROR**, **INFO**, **DEBUG**.
  The default level is **INFO**.
  - **OFF** — logging is fully disabled
    (both sinks — os_log and file — stop writing).
  - **ERROR** — only errors and failures.
  - **INFO** — errors + key lifecycle events:
    start/stop of recording, audio device selection,
    device switching, API call results,
    user actions (button presses, hotkeys).
  - **DEBUG** — everything: audio stream parameters,
    intermediate states, timings,
    full payload of API requests and responses
    (except confidential data).
- Errors (ERROR) MUST be logged at the
  ERROR, INFO, and DEBUG levels. In OFF mode, logging
  is fully disabled, including errors.
  Each ERROR message MUST contain context:
  the method name, call parameters, and error description.
- Logging MUST use `os.Logger`
  (Unified Logging System). Each module/service MUST
  create its own `os.Logger` instance
  with a unique category (subsystem + category)
  for filtering in Console.app.
- Logs MUST be output simultaneously to the **console**
  (Console.app / Xcode Console) and to a **file**.

### File logging

- Log files MUST be rotated every **1 hour**.
- Log files older than **24 hours** MUST be deleted
  automatically.
- The retention period (24 hours by default) MUST be
  configurable in the application's advanced settings.
- Log files MUST be located in the application's standard
  Application Support directory.

### Logging level configuration

- The logging level MUST be configurable
  in the application's **Advanced Settings**.
- Switching the level MUST take effect immediately,
  without restarting the application.

### Event categories

The following event categories MUST be logged:

- **Bluetooth / AirPods**: discovery, connection,
  disconnection, profile change (A2DP ↔ HFP/SCO),
  loss of connection with the device.
- **Audio devices**: enumeration of available devices,
  start of device use, switching
  between devices, active audio stream parameters
  (sample rate, channels, format).
- **Audio recording**: AVAudioEngine initialization,
  input node setup, tap start/stop,
  audio format configuration.
- **Permissions**: microphone access request
  (AVCaptureDevice.requestAccess), request result,
  Accessibility check (AXIsProcessTrusted),
  permission status change.
- **API requests**: URL, HTTP method, payload size,
  response status, execution time; in DEBUG mode —
  full payload of request and response (headers without API key,
  request body, response body).
- **User actions**: hotkey press, button presses
  in the UI, prompt/language selection, settings change
  (old → new value, except API key).
- **System calls**: interaction with CGEvent,
  NSPasteboard, NSWorkspace, SMAppService.
- **Lifecycle**: application startup, termination,
  transition to background, return to active state.

### Logging security

- It is PROHIBITED to log confidential data
  (API keys, audio buffer contents, recognized text)
  — use `\(value, privacy: .private)`.
- In log files, confidential data MUST be
  masked (for example, `sk-...XXXX`).

**Rationale**: interaction with Bluetooth devices,
the audio subsystem, system permissions, and external APIs
produces hard-to-reproduce bugs; structured
logging to the console and file is the only reliable
way to diagnose them. File logging with rotation
allows analyzing problems retrospectively,
without requiring real-time reproduction.

---

## Technical stack

| Component               | Technology                              |
|-------------------------|-----------------------------------------|
| Language                | Swift 5.9+                              |
| UI framework            | SwiftUI                                 |
| Minimum OS              | macOS 15 (Sequoia)                      |
| Target OS               | macOS 15 (Sequoia), macOS 26 (Tahoe) and higher |
| Dependency management   | Swift Package Manager                   |
| Audio capture           | AVFoundation (AVAudioEngine)            |
| Speech-to-Text API      | OpenAI Whisper API                      |
| Text formatting         | OpenAI Chat Completions API             |
| Settings storage        | UserDefaults / @AppStorage              |
| Secrets storage         | macOS Keychain (Security framework)     |
| Global hotkey           | CGEvent / Carbon (RegisterEventHotKey)  |
| Architecture            | MVVM + Observation framework            |
| Logging                 | os.Logger (Unified Logging) + file      |
| Testing                 | XCTest / Swift Testing                  |
| Linting                 | SwiftLint                               |
| CI/CD                   | Xcode Cloud or GitHub Actions           |

---

## Governance

### Amendment procedure

1. The amendment author MUST describe the proposed change
   and rationale in ADR (Architecture Decision Record) format.
2. Changes to principles require explicit approval from the project
   owner.
3. After approval, the constitution is updated via the
   `/speckit.constitution` command with the changes specified.
4. All dependent artifacts MUST be checked for
   compatibility (see Sync Impact Report).

### Versioning

- **MAJOR**: removal or incompatible change of principles.
- **MINOR**: addition of a new principle or substantial
  expansion of an existing one.
- **PATCH**: clarification of wording, typo fixes.

### Compliance check

- Every specification (`spec.md`) MUST pass
  a check for compliance with the constitution's principles
  at the `Constitution Check` stage in `plan.md`.
- `/speckit.verify` MUST check that the
  implementation complies with the constitution's principles.
- Violations of principles not documented
  in `Complexity Tracking` are considered defects.
