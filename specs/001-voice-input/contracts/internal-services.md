# Internal Service Contracts

**Feature**: 001-voice-input
**Date**: 2026-03-04
**Updated**: 2026-03-05

---

## Data Flow Diagram

```
┌─────────────┐     ┌──────────────────┐     ┌────────────────────┐
│ HotkeyService│────▶│ RecordingViewModel │────▶│  OverlayPanel      │
│ (global hotkey)│  │  (coordinator)    │    │  (NSPanel, SwiftUI) │
└─────────────┘     └────────┬─────────┘     └────────────────────┘
                             │
                    ┌────────┼────────┐
                    ▼        ▼        ▼
          ┌──────────┐ ┌─────────┐ ┌──────────┐
          │AudioCapture│ │Transcrip│ │Formatting│
          │ Service    │ │tion Svc │ │ Service  │
          │(AVAudio    │ │(OpenAI  │ │(Chat API)│
          │ Engine)    │ │ Audio)  │ │          │
          └──────────┘ └─────────┘ └──────────┘
                                        │
                                        ▼
                                  ┌──────────┐
                                  │ PasteService│
                                  │(CGEvent +  │
                                  │ NSPaste-   │
                                  │ board)     │
                                  └──────────┘

Additional services:
  PromptsStore ─── JSON in Application Support
  AppSettings ──── UserDefaults + Keychain
```

---

## Contract: AudioCaptureService

### Responsibility

Capture audio from the microphone via AVAudioEngine, convert to WAV in-memory.

### Interface

```swift
protocol AudioCaptureServiceProtocol {
    /// Current volume level (0.0–1.0), updated in real time.
    /// Used for the visual indicator.
    var audioLevel: Float { get }

    /// Current recording duration in seconds.
    var currentDuration: TimeInterval { get }

    /// Start recording from the specified device.
    /// - deviceID: audio device identifier (nil = system default)
    func startRecording(deviceID: String?) throws

    /// Stop recording. Returns WAV Data (PCM Int16, 16 kHz, mono).
    func stopRecording() async throws -> Data

    /// Reset the current recording without sending.
    func resetRecording()

    /// List of available audio input devices.
    func availableInputDevices() -> [(id: String, name: String)]
}
```

### Preconditions

- Microphone permission granted (`AVAudioApplication.requestRecordPermission`)
- Microphone is physically available
- When `deviceID != nil` — a device with the given ID is available (otherwise fallback to system)

### Postconditions

- `stopRecording()` returns a valid WAV with a 44-byte RIFF header
- Audio is NOT saved to disk (only in-memory buffers)
- After `resetRecording()` the buffers are cleared
- When `maxRecordingDuration` or 25 MB is reached — auto-stop (delegated via callback)

### Errors

- `RecordingError.microphoneNotAvailable` — no audio device
- `RecordingError.microphonePermissionDenied` — permission not granted
- `RecordingError.fileSizeLimitReached` — size exceeded 25 MB

---

## Contract: TranscriptionService

### Responsibility

Send audio data to OpenAI Audio Transcriptions API, receive text transcription.

### Interface

```swift
protocol TranscriptionServiceProtocol {
    /// Recognize audio.
    /// - audioData: WAV Data
    /// - language: ISO 639-1 voice language code (nil = auto-detect)
    /// - model: transcription model (selected by the user)
    /// - Returns: recognized text
    func transcribe(
        audioData: Data,
        language: String?,
        model: STTModel
    ) async throws -> String
}
```

### Preconditions

- API key configured (not empty)
- Network is available
- `audioData` contains valid WAV
- `model` is one of the supported models

### Postconditions

- Returns a non-empty string with the recognized text
- On empty result — `RecordingError.silenceDetected`
- Uses `response_format: "json"` for compatibility across all models

---

## Contract: FormattingService

### Responsibility

Post-process text via OpenAI Chat Completions API with a configurable system prompt and output language.

### Interface

```swift
protocol FormattingServiceProtocol {
    /// Format the text.
    /// - text: source text from the transcription API
    /// - systemPrompt: prompt content from settings
    /// - textLanguage: ISO 639-1 output language code
    /// - model: LLM model (selected by the user)
    /// - Returns: formatted text with Markdown
    func format(
        text: String,
        systemPrompt: String,
        textLanguage: String,
        model: LLMModel
    ) async throws -> String
}
```

### Preconditions

- API key configured
- `text` is not empty
- `systemPrompt` is not empty
- `model` is one of the supported models

### Postconditions

- Returns text with Markdown formatting
- Output language is specified in the system prompt: `"{systemPrompt}\n\nResponse language: {textLanguage}"`
- On API error — `RecordingError.formattingFailed`

---

## Contract: PasteService

### Responsibility

Paste text into the previously active text field via NSPasteboard + CGEvent Cmd+V.

### Interface

```swift
protocol PasteServiceProtocol {
    /// Paste text into the previously active application.
    /// Writes to NSPasteboard, simulates Cmd+V, restores the clipboard.
    func pasteText(_ text: String) async throws

    /// Copy Markdown source to the clipboard.
    func copyToClipboard(_ text: String)
}
```

### Preconditions (pasteText)

- Accessibility permission granted
- Target application is running (PID saved at overlay show)

### Postconditions (pasteText)

- Text inserted into the target field
- Original clipboard contents restored (~200ms delay)
- When the target application is unavailable — text remains in the clipboard, a notification is shown

---

## Contract: KeychainService

### Interface

```swift
protocol KeychainServiceProtocol {
    func save(_ value: String, forKey key: String) throws
    func retrieve(forKey key: String) throws -> String?
    func delete(forKey key: String) throws
}
```

### Keys

| Key | Description |
|---|---|
| `openai-api-key` | OpenAI API key |

---

## Contract: APIKeyValidationService

### Responsibility

Validate the API key when entered in settings (FR-011b).

### Interface

```swift
protocol APIKeyValidationServiceProtocol {
    /// Validate the API key with a test request to GET /v1/models.
    /// - apiKey: key to validate
    /// - Returns: true if the key is valid
    func validate(apiKey: String) async throws -> Bool
}
```

### Preconditions

- Network is available

### Postconditions

- Returns `true` on HTTP 200
- Returns `false` on HTTP 401
- Throws on network errors

---

## Contract: PromptsStore

### Responsibility

Management of named prompts. Persistence to a JSON file.

### Interface

```swift
@Observable
class PromptsStore {
    var prompts: [SystemPrompt]

    var defaultPrompt: SystemPrompt? { get }

    func add(_ prompt: SystemPrompt)
    func update(_ prompt: SystemPrompt)
    func delete(id: UUID)
    func setDefault(id: UUID)
    func save() throws
    func load() throws
}
```

### Preconditions

- Directory `~/Library/Application Support/Verborra/` exists (created on first `save()`)

### Postconditions

- There is always at least one prompt
- Exactly one prompt has `isDefault == true`
- When the default prompt is deleted — the next one becomes the default
- The JSON file is valid and can be deserialized

### File Path

```
~/Library/Application Support/Verborra/prompts.json
```

---

## Contract: RecordingViewModel

### Responsibility

Coordinate the entire flow: overlay → recording → transcription → formatting → paste.

### State

```swift
@Observable
class RecordingViewModel {
    var state: RecordingState = .idle
    var audioLevel: Float = 0.0
    var currentDuration: TimeInterval = 0.0
    var result: TranscriptionResult?
    var editedText: String = ""

    // Overlay-specific settings (per-session)
    var selectedPrompt: SystemPrompt?       // Selected prompt (from PromptsStore)
    var selectedVoiceLanguage: String = ""  // Voice language (from prompt, may be changed)
    var selectedTextLanguage: String = ""   // Text language (from prompt, may be changed)
}
```

### Methods

```swift
extension RecordingViewModel {
    func showOverlay()           // Remember target PID, show NSPanel,
                                 // load default prompt and languages
    func startRecording()        // idle → recording (with selectedAudioDeviceID)
    func stopRecording()         // recording → processing → result/error
    func resetRecording()        // recording → idle (reset)
    func changePrompt(_ prompt: SystemPrompt)
                                 // Update prompt + languages;
                                 // if state == .result → re-run AI processing
    func changeVoiceLanguage(_ lang: String)  // Update voice language
    func changeTextLanguage(_ lang: String)   // Update text language
    func pasteResult()           // result → hide overlay, paste text
    func copyResult()            // result → copy to clipboard
    func dismissOverlay()        // close overlay without pasting
}
```

### Prompt Change Logic

1. **During recording or before recording**: update `selectedPrompt`, `selectedVoiceLanguage`, `selectedTextLanguage`. Applied when sent for processing.
2. **After receiving a result**: update the prompt, transition to `processing`, re-send `result.audioData` for transcription + formatting with the new prompt.
