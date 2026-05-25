# Data Model: Voice Text Input

**Feature**: 001-voice-input
**Date**: 2026-03-04
**Updated**: 2026-03-04

---

## Overview

The application does not use a database. All data is in-memory (recording, result) or UserDefaults/Keychain/JSON (settings, prompts). Recording history is not stored.

---

## Entities

### RecordingState (enum)

State of the recording and recognition process.

```swift
enum RecordingState: Equatable {
    case idle                              // Idle — initial state
    case recording(duration: TimeInterval) // Recording in progress, current duration
    case processing                        // Sending for recognition + formatting
    case result(text: String)              // Ready formatted text
    case error(RecordingError)             // Error at any stage
}
```

**State transitions:**

```
idle → recording     (user pressed "Start recording" / Space / auto-record)
recording → idle     (user pressed Delete — reset)
recording → processing (user pressed "Stop" / Space / limit reached)
processing → result  (transcription + formatting complete)
processing → error   (API error, network, empty result)
result → processing  (user changed prompt → re-AI processing)
result → idle        (user inserted/closed overlay)
error → idle         (user closed overlay)
error → recording    (user started recording again)
```

### RecordingError (enum)

```swift
enum RecordingError: Equatable {
    case microphoneNotAvailable         // Microphone not available
    case microphonePermissionDenied     // Permission not granted
    case apiKeyNotConfigured            // API key not set
    case networkUnavailable             // No network connection
    case transcriptionFailed(String)    // Transcription API error
    case formattingFailed(String)       // Chat Completions API error
    case silenceDetected                // Speech not detected
    case fileSizeLimitReached           // 25 MB limit exceeded
}
```

### TranscriptionResult (struct)

Result of recognizing a single recording. Lives in-memory until insertion/closing the overlay.

```swift
struct TranscriptionResult {
    let rawText: String                 // Source text from transcription API
    var formattedText: String           // Text after AI formatting
    let voiceLanguage: String           // Voice language at recording (ISO 639-1)
    let textLanguage: String            // Text language at processing (ISO 639-1)
    let timestamp: Date                 // Creation time
    let audioDuration: TimeInterval     // Recording duration
    let audioData: Data                 // WAV data for re-processing
}
```

**Lifecycle**: created when the API response is received → user edits `formattedText` → on prompt change `audioData` is re-sent for AI processing → insertion/copy/close → the object is destroyed.

### SystemPrompt (struct, Codable)

Named prompt for AI formatting. Stored in a JSON file.

```swift
struct SystemPrompt: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String                    // Display name of the prompt
    var content: String                 // Markdown content of the prompt
    var isDefault: Bool                 // Whether assigned as default
    var voiceLanguage: String           // Default voice language (ISO 639-1)
    var textLanguage: String            // Default text language (ISO 639-1)
}
```

### STTModel (enum, Codable)

Speech transcription model.

```swift
enum STTModel: String, Codable, CaseIterable {
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"  // Default, $0.003/min
    case gpt4oTranscribe = "gpt-4o-transcribe"           // $0.006/min
    case whisper1 = "whisper-1"                           // $0.006/min
}
```

### LLMModel (enum, Codable)

Text processing model.

```swift
enum LLMModel: String, Codable, CaseIterable {
    case gpt41Nano = "gpt-4.1-nano"     // Default, $0.10/$0.40 per 1M tokens
    case gpt4oMini = "gpt-4o-mini"      // $0.15/$0.60
    case gpt41Mini = "gpt-4.1-mini"     // $0.40/$1.60
    case gpt5Nano = "gpt-5-nano"        // $0.05/$0.40
}
```

### SupportedLanguage (enum)

Available languages for voice and text.

```swift
enum SupportedLanguage: String, CaseIterable {
    case english = "en"
    case russian = "ru"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case portuguese = "pt"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case italian = "it"

    var displayName: String {
        switch self {
        case .english: "English"
        case .russian: "Russian"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .portuguese: "Português"
        case .chinese: "中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .italian: "Italiano"
        }
    }
}
```

### MaxRecordingDuration (enum)

Configurable maximum recording duration.

```swift
enum MaxRecordingDuration: Int, CaseIterable, Codable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case twentyMinutes = 1200

    var displayName: String {
        switch self {
        case .oneMinute: "1 min"
        case .fiveMinutes: "5 min"
        case .tenMinutes: "10 min"
        case .twentyMinutes: "20 min"
        }
    }
}
```

### AppSettings (@Observable)

Application settings. Simple settings are stored in UserDefaults.

```swift
@Observable
class AppSettings {
    // UserDefaults / @AppStorage
    var launchAtLogin: Bool             // Auto-launch, default: true
    var autoRecord: Bool                // Auto-record on overlay open, default: true
    var maxRecordingDuration: MaxRecordingDuration  // default: .fiveMinutes
    var selectedAudioDeviceID: String?  // Audio device ID, nil = system
    var selectedSTTModel: STTModel      // default: .gpt4oMiniTranscribe
    var selectedLLMModel: LLMModel      // default: .gpt41Nano

    // Keychain (via KeychainService)
    var apiKey: String                  // OpenAI API key (read/write via Keychain)

    // KeyboardShortcuts (via library)
    // The hotkey is stored automatically in UserDefaults via KeyboardShortcuts
}
```

**Default values:**

| Parameter | Default value |
|---|---|
| `launchAtLogin` | `true` |
| `autoRecord` | `true` |
| `maxRecordingDuration` | `.fiveMinutes` (300 sec) |
| `selectedAudioDeviceID` | `nil` (system device) |
| `selectedSTTModel` | `.gpt4oMiniTranscribe` |
| `selectedLLMModel` | `.gpt41Nano` |
| `apiKey` | `""` (empty — requires setup) |
| Global hotkey | `Option+Space` |

### PromptsStore (@Observable)

Management of named prompts. Stores prompts in a JSON file.

```swift
@Observable
class PromptsStore {
    var prompts: [SystemPrompt]

    var defaultPrompt: SystemPrompt? {
        prompts.first(where: { $0.isDefault })
    }

    func add(_ prompt: SystemPrompt)
    func update(_ prompt: SystemPrompt)
    func delete(id: UUID)
    func setDefault(id: UUID)

    // Persistence
    func save() throws       // Write to ~/Library/Application Support/Verborra/prompts.json
    func load() throws       // Read from JSON file
}
```

**Default prompt (created on first launch):**

| Field | Value |
|---|---|
| `name` | "Standard" |
| `content` | "Fix punctuation, place paragraphs, and add Markdown formatting (headings, lists, emphasis). Return only the corrected text without explanations." |
| `isDefault` | `true` |
| `voiceLanguage` | Determined by macOS system language |
| `textLanguage` | Determined by macOS system language |

---

## Data Storage

| Data | Mechanism | Location |
|---|---|---|
| Simple settings | `@AppStorage` / `UserDefaults` | `~/Library/Preferences/` |
| API key | macOS Keychain (Security framework) | System Keychain |
| Global hotkey | `UserDefaults` (via KeyboardShortcuts) | `~/Library/Preferences/` |
| Named prompts | JSON file (`Codable`) | `~/Library/Application Support/Verborra/prompts.json` |
| Auto-launch | `SMAppService` (ServiceManagement) | System Login Items |
| Audio recording | In-memory `[AVAudioPCMBuffer]` | RAM |
| Recognition result | In-memory `TranscriptionResult` | RAM |

---

## Service Protocols

All services are abstracted via protocols for testing (Principle 5).

### AudioCaptureServiceProtocol

```swift
protocol AudioCaptureServiceProtocol {
    var audioLevel: Float { get }       // Current volume level (0.0–1.0)
    var currentDuration: TimeInterval { get }  // Current recording duration
    func startRecording(deviceID: String?) throws
    func stopRecording() async throws -> Data  // WAV Data
    func resetRecording()
}
```

### TranscriptionServiceProtocol

```swift
protocol TranscriptionServiceProtocol {
    func transcribe(
        audioData: Data,
        language: String?,
        model: STTModel
    ) async throws -> String
}
```

### FormattingServiceProtocol

```swift
protocol FormattingServiceProtocol {
    func format(
        text: String,
        systemPrompt: String,
        textLanguage: String,
        model: LLMModel
    ) async throws -> String
}
```

### KeychainServiceProtocol

```swift
protocol KeychainServiceProtocol {
    func save(_ value: String, forKey key: String) throws
    func retrieve(forKey key: String) throws -> String?
    func delete(forKey key: String) throws
}
```

### PasteServiceProtocol

```swift
protocol PasteServiceProtocol {
    func pasteText(_ text: String) async throws
    func copyToClipboard(_ text: String)
}
```

### APIKeyValidationServiceProtocol

```swift
protocol APIKeyValidationServiceProtocol {
    func validate(apiKey: String) async throws -> Bool
}
```
