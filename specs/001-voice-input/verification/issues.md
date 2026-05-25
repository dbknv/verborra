# Issue Registry: 001-voice-input

**Created**: 2026-03-05
**Updated**: 2026-03-05 (fix of all issues)
**Verification**: V001–V024

---

## Critical Issues (critical)

### V001 | T034 | PasteService.swift | critical | `accessibility_missing_check`

**Description**: PasteService was missing an Accessibility permission check before attempting CGEvent paste.
**Fix**: Added `guard AXIsProcessTrusted()` that throws `PasteError.accessibilityNotGranted`, text is saved to the clipboard. Added new error cases `accessibilityNotGranted` and `pasteTargetUnavailable` to `RecordingError`. In `RecordingViewModel.pasteResult()` added error handling that shows a message in the overlay.
**Affected files**: `PasteService.swift`, `RecordingState.swift`, `RecordingViewModel.swift`, `RecordingView.swift`
**Status**: fixed

---

## High Severity Issues (high)

### V002 | T004 | Package.swift | high | `missing_dependency`

**Description**: SPM dependency KeyboardShortcuts (>=2.0.0) was missing in Package.swift.
**Fix**: Added `.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")` to dependencies and a product dependency in the target.
**Status**: fixed

### V003 | T022 | HotkeyService.swift | high | `spec_deviation`

**Description**: HotkeyService used raw Carbon API `RegisterEventHotKey` instead of the KeyboardShortcuts library.
**Fix**: Completely rewritten using `KeyboardShortcuts.onKeyDown(for: .toggleOverlay)`. Defined `KeyboardShortcuts.Name.toggleOverlay` with default Option+Space.
**Status**: fixed

### V004 | T037 | HotkeyRecorder.swift | high | `stub_implementation`

**Description**: HotkeyRecorder is a stub displaying static text.
**Fix**: Replaced with `KeyboardShortcuts.Recorder(for: .toggleOverlay)`.
**Status**: fixed

### V005 | T024 | RecordingViewModel.swift | high | `missing_feature`

**Description**: When voice language was changed in the `.result` state, re-transcription was not performed.
**Fix**: Added `retranscribeAndReformat()` method for full re-transcription with the new language + re-formatting. Called from `changeVoiceLanguage()` when audio data is present in the result.
**Affected files**: `RecordingViewModel.swift`, `TranscriptionResult.swift` (rawText and voiceLanguage became var)
**Status**: fixed

### V006 | T032 | PasteService.swift | high | `missing_notification`

**Description**: When the target application for paste was unavailable, no user notification was shown.
**Fix**: Added `NSRunningApplication(processIdentifier: targetPID)` check that throws `PasteError.targetAppUnavailable`. RecordingViewModel shows the `.pasteTargetUnavailable` error in the overlay.
**Status**: fixed

### V007 | T040 | SettingsView.swift | high | `spec_deviation`

**Description**: STT and LLM model selectors were in the "General" tab instead of the "System prompts" tab.
**Fix**: Moved to PromptsSettingsTab with popover tooltips (?). Added `infoDescription` to STTModel and LLMModel.
**Status**: fixed

---

## Medium Severity Issues (medium)

### V008 | T019 | AudioCaptureService.swift | medium | `logic_error`

**Description**: Microphone permission check used `isInputMuted` instead of `recordPermission`.
**Fix**: Replaced with `AVCaptureDevice.authorizationStatus(for: .audio)`.
**Status**: fixed

### V009 | T020 | TranscriptionService.swift | medium | `logic_error`

**Description**: HTTP 400 errors were incorrectly retried.
**Fix**: Added a separate case 400 with an immediate throw.
**Status**: fixed

### V010 | T030 | RecordingView.swift | medium | `missing_ui_element`

**Description**: An explicit "Retry" button for API errors was missing.
**Fix**: Added "Retry" button that calls `viewModel.retryFromError()` for transcription, formatting, network, and silence errors. Also added a button to go to System Settings for Accessibility errors.
**Status**: fixed

### V011 | T030 | RecordingViewModel.swift | medium | `spec_deviation`

**Description**: Pressing Space in the error state started a new recording instead of resending the saved audio.
**Fix**: Added `retryFromError()` method — if audio data is saved in `result.audioData`, repeat transcription + formatting.
**Status**: fixed

### V012 | T039 | SettingsView.swift | medium | `missing_feature`

**Description**: Accessibility and Microphone permission check buttons were missing.
**Fix**: Added a "Permissions" section with check buttons and status indicators. Added `checkAccessibilityPermission()` and `checkMicrophonePermission()` to SettingsViewModel.
**Status**: fixed

### V013 | T031 | ResultView.swift | medium | `missing_feature`

**Description**: Markdown list styling was not implemented.
**Fix**: Added styling of `UnorderedList` and `OrderedList` with indents via `NSMutableParagraphStyle`.
**Status**: fixed

### V014 | T038 | SettingsView.swift | medium | `spec_deviation`

**Description**: Standard TabView used instead of macOS Ventura sidebar style.
**Fix**: Replaced TabView with `NavigationSplitView` with a sidebar and a dynamic window size.
**Status**: fixed

### V015 | T041 | SettingsView.swift | medium | `missing_feature`

**Description**: License and links were missing in the "About" tab.
**Fix**: Added: license (MIT), links to documentation and support.
**Status**: fixed

### V016 | T024 | RecordingViewModel.swift | medium | `contract_deviation`

**Description**: `selectedPrompt` declared as non-optional, although the contract specifies `SystemPrompt?`.
**Fix**: The deviation is insignificant — the prompt is always initialized from `defaultPrompt`, null is impossible at runtime.
**Status**: wont_fix (by design)

---

## Test Issues (high)

### V017 | T046 | TranscriptionServiceTests.swift | high | `insufficient_test_coverage`

**Description**: Tests for multipart/form-data, retry, timeout were missing.
**Fix**: Added tests: multipart body, retry on 429/500, no retry on 400, 60s timeout.
**Status**: fixed

### V018 | T047 | FormattingServiceTests.swift | high | `insufficient_test_coverage`

**Description**: Tests for JSON body, temperature, timeout, textLanguage were missing.
**Fix**: Added tests: request body fields, textLanguage in system prompt, 30s timeout, retry on 429.
**Status**: fixed

### V019 | T048 | KeychainServiceTests.swift | high | `test_only_mocks`

**Description**: Tests only verified MockKeychainService.
**Fix**: Added tests for the real KeychainService (save/retrieve/delete/overwrite) with cleanup in tearDown.
**Status**: fixed

---

## Low Severity Issues (low)

### V020 | T019 | AudioCaptureService.swift | low | `data_race`

**Description**: Data race on `audioLevel` and `currentDuration`.
**Fix**: Updates wrapped in `DispatchQueue.main.async`.
**Status**: fixed

### V021 | T019 | AudioCaptureService.swift | low | `edge_case`

**Description**: The last buffer was lost on auto-stop.
**Fix**: The buffer is appended to the array before calling `triggerAutoStop()`.
**Status**: fixed

### V022 | T029 | OverlayContentView.swift | low | `keyboard_conflict`

**Description**: Space/Delete did not work in the `.result` state due to NSTextView being the first responder.
**Fix**: `handleKeyDown` returns false for Space/Delete in the `.result` state, allowing NSTextView to handle them.
**Status**: fixed

### V023 | T044 | RecordingViewModel.swift | low | `missing_navigation`

**Description**: On the "API key not configured" error there is no button to go to Settings.
**Fix**: The button already existed in RecordingView.swift (lines 92-97). Issue closed.
**Status**: wont_fix (already exists)

### V024 | T032 | PasteService.swift | low | `clipboard_data_loss`

**Description**: Clipboard snapshot only saved string data.
**Fix**: Save all data types from the pasteboard via `pasteboardItems`.
**Status**: fixed
