import Carbon
import CoreAudio
import Foundation
import SwiftUI

// MARK: - AppSettings (T013)

@Observable
final class AppSettings {
    private let keychainService: KeychainServiceProtocol
    private static let apiKeyKeychainKey = "openai-api-key"

    @ObservationIgnored
    @AppStorage("autoRecord")
    var autoRecord: Bool = true

    @ObservationIgnored
    @AppStorage("maxRecordingDurationRawValue")
    private var maxRecordingDurationRawValue: Int = MaxRecordingDuration.default.rawValue

    var maxRecordingDuration: MaxRecordingDuration {
        get {
            access(keyPath: \.maxRecordingDuration)
            return MaxRecordingDuration(rawValue: maxRecordingDurationRawValue) ?? .default
        }
        set {
            withMutation(keyPath: \.maxRecordingDuration) {
                maxRecordingDurationRawValue = newValue.rawValue
            }
        }
    }

    @ObservationIgnored
    @AppStorage("selectedAudioDeviceID")
    var selectedAudioDeviceID: String = ""

    var selectedAudioDeviceIDOrNil: String? {
        get {
            access(keyPath: \.selectedAudioDeviceIDOrNil)
            return selectedAudioDeviceID.isEmpty ? nil : selectedAudioDeviceID
        }
        set {
            withMutation(keyPath: \.selectedAudioDeviceIDOrNil) {
                selectedAudioDeviceID = newValue ?? ""
            }
        }
    }

    // MARK: - Audio Device UID (009-audio-device-selector)

    @ObservationIgnored
    @AppStorage("selectedAudioDeviceUID")
    private var _selectedAudioDeviceUID: String = ""

    /// UID of the selected audio device. Empty string = System Default.
    var selectedAudioDeviceUID: String {
        get {
            access(keyPath: \.selectedAudioDeviceUID)
            return _selectedAudioDeviceUID
        }
        set {
            withMutation(keyPath: \.selectedAudioDeviceUID) {
                _selectedAudioDeviceUID = newValue
            }
        }
    }

    @ObservationIgnored
    @AppStorage("isAudioSaveEnabled")
    private var _isAudioSaveEnabled: Bool = false

    /// Whether audio recording to disk is enabled (Advanced Settings, opt-in).
    var isAudioSaveEnabled: Bool {
        get {
            access(keyPath: \.isAudioSaveEnabled)
            return _isAudioSaveEnabled
        }
        set {
            withMutation(keyPath: \.isAudioSaveEnabled) {
                _isAudioSaveEnabled = newValue
            }
        }
    }

    /// Security-Scoped Bookmark data for the audio save folder.
    var audioSaveFolderBookmark: Data? {
        get {
            access(keyPath: \.audioSaveFolderBookmark)
            return UserDefaults.standard.data(forKey: "audioSaveFolderBookmark")
        }
        set {
            withMutation(keyPath: \.audioSaveFolderBookmark) {
                UserDefaults.standard.set(newValue, forKey: "audioSaveFolderBookmark")
            }
        }
    }

    /// Create and save a Security-Scoped Bookmark for the given folder URL.
    func saveAudioFolderBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            audioSaveFolderBookmark = bookmarkData
        } catch {
            // Bookmark creation failed — will be handled by caller
        }
    }

    /// Resolve the saved bookmark into a usable URL. Refreshes bookmark if stale.
    func resolveAudioFolderBookmark() -> URL? {
        guard let data = audioSaveFolderBookmark else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                saveAudioFolderBookmark(for: url)
            }
            return url
        } catch {
            return nil
        }
    }

    /// Migrate old `selectedAudioDeviceID` (numeric) to `selectedAudioDeviceUID` (stable string).
    func migrateAudioDeviceIDToUID(devices: [AudioDevice]) {
        let oldID = selectedAudioDeviceID
        guard !oldID.isEmpty else { return }
        // Old key stored AudioDeviceID as string — try to match with current devices
        if let numericID = AudioDeviceID(oldID),
           let device = devices.first(where: { $0.audioDeviceID == numericID }) {
            selectedAudioDeviceUID = device.uid
        }
        // Clear old key after migration
        selectedAudioDeviceID = ""
    }

    @ObservationIgnored
    @AppStorage("selectedSTTModelRawValue")
    private var selectedSTTModelRawValue: String = STTModel.default.rawValue

    var selectedSTTModel: STTModel {
        get {
            access(keyPath: \.selectedSTTModel)
            return STTModel(rawValue: selectedSTTModelRawValue) ?? .default
        }
        set {
            withMutation(keyPath: \.selectedSTTModel) {
                selectedSTTModelRawValue = newValue.rawValue
            }
        }
    }

    @ObservationIgnored
    @AppStorage("selectedLLMModelRawValue")
    private var selectedLLMModelRawValue: String = LLMModel.default.rawValue

    var selectedLLMModel: LLMModel {
        get {
            access(keyPath: \.selectedLLMModel)
            return LLMModel(rawValue: selectedLLMModelRawValue) ?? .default
        }
        set {
            withMutation(keyPath: \.selectedLLMModel) {
                selectedLLMModelRawValue = newValue.rawValue
            }
        }
    }

    @ObservationIgnored
    @AppStorage("launchAtLogin")
    var launchAtLogin: Bool = true

    @ObservationIgnored
    @AppStorage("recordingKeyCode")
    var recordingKeyCode: Int = 49  // Space

    @ObservationIgnored
    @AppStorage("recordingModifiers")
    var recordingModifiers: Int = 0  // No modifiers

    var recordingKeyDisplayName: String {
        let knownKeys: [Int: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
            76: "Enter", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12",
        ]
        if let name = knownKeys[recordingKeyCode] {
            return name
        }
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(recordingKeyCode)"
        }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0
        UCKeyTranslate(keyboardLayout, UInt16(recordingKeyCode), UInt16(kUCKeyActionDown),
                        0, UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState, chars.count, &length, &chars)
        guard length > 0 else { return "Key \(recordingKeyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    @ObservationIgnored
    @AppStorage("globalVoiceLanguage")
    private var globalVoiceLanguageRawValue: String = ""

    var globalVoiceLanguage: SupportedLanguage {
        get {
            access(keyPath: \.globalVoiceLanguage)
            if globalVoiceLanguageRawValue.isEmpty {
                return .ru
            }
            return SupportedLanguage(rawValue: globalVoiceLanguageRawValue) ?? .ru
        }
        set {
            withMutation(keyPath: \.globalVoiceLanguage) {
                globalVoiceLanguageRawValue = newValue.rawValue
            }
        }
    }

    @ObservationIgnored
    @AppStorage("globalTextLanguage")
    private var globalTextLanguageRawValue: String = ""

    var globalTextLanguage: SupportedLanguage {
        get {
            access(keyPath: \.globalTextLanguage)
            if globalTextLanguageRawValue.isEmpty {
                return .ru
            }
            return SupportedLanguage(rawValue: globalTextLanguageRawValue) ?? .ru
        }
        set {
            withMutation(keyPath: \.globalTextLanguage) {
                globalTextLanguageRawValue = newValue.rawValue
            }
        }
    }

    @ObservationIgnored
    @AppStorage("uiLanguage")
    private var uiLanguageRawValue: String = ""

    var uiLanguage: SupportedLanguage {
        get {
            access(keyPath: \.uiLanguage)
            if uiLanguageRawValue.isEmpty {
                return LocalizationManager.detectSystemLanguage()
            }
            return SupportedLanguage(rawValue: uiLanguageRawValue) ?? .en
        }
        set {
            withMutation(keyPath: \.uiLanguage) {
                uiLanguageRawValue = newValue.rawValue
                LocalizationManager.shared.currentLanguage = newValue
                NotificationCenter.default.post(
                    name: .uiLanguageDidChange,
                    object: nil,
                    userInfo: ["language": newValue]
                )
            }
        }
    }

    // MARK: - Logging (T014)

    @ObservationIgnored
    @AppStorage("logLevel")
    private var logLevelRawValue: Int = LogLevel.info.rawValue

    var logLevel: LogLevel {
        get {
            access(keyPath: \.logLevel)
            return LogLevel(rawValue: logLevelRawValue) ?? .info
        }
        set {
            withMutation(keyPath: \.logLevel) {
                logLevelRawValue = newValue.rawValue
            }
        }
    }

    @ObservationIgnored
    @AppStorage("logRetentionHours")
    private var _logRetentionHours: Int = 24

    var logRetentionHours: Int {
        get {
            access(keyPath: \.logRetentionHours)
            return _logRetentionHours
        }
        set {
            withMutation(keyPath: \.logRetentionHours) {
                _logRetentionHours = max(1, min(168, newValue))
            }
        }
    }

    @ObservationIgnored
    @AppStorage("onboardingCompleted")
    private var _isOnboardingCompleted: Bool = false

    var isOnboardingCompleted: Bool {
        get {
            access(keyPath: \.isOnboardingCompleted)
            return _isOnboardingCompleted
        }
        set {
            withMutation(keyPath: \.isOnboardingCompleted) {
                _isOnboardingCompleted = newValue
            }
        }
    }

    // MARK: - Personal Preferences (012-vocabularies)

    @ObservationIgnored
    @AppStorage("personalPreferencesText")
    private var _personalPreferencesText: String = ""

    var personalPreferencesText: String {
        get {
            access(keyPath: \.personalPreferencesText)
            return _personalPreferencesText
        }
        set {
            withMutation(keyPath: \.personalPreferencesText) {
                _personalPreferencesText = newValue
            }
        }
    }

    @ObservationIgnored
    private var _cachedApiKey: String?

    var apiKey: String {
        get {
            access(keyPath: \.apiKey)
            if let cached = _cachedApiKey {
                return cached
            }
            let value = (try? keychainService.retrieve(forKey: Self.apiKeyKeychainKey)) ?? ""
            _cachedApiKey = value
            return value
        }
        set {
            withMutation(keyPath: \.apiKey) {
                _cachedApiKey = newValue
                if newValue.isEmpty {
                    try? keychainService.delete(forKey: Self.apiKeyKeychainKey)
                } else {
                    try? keychainService.save(newValue, forKey: Self.apiKeyKeychainKey)
                }
            }
        }
    }

    var hasApiKey: Bool {
        !apiKey.isEmpty
    }

    init(keychainService: KeychainServiceProtocol = KeychainService()) {
        self.keychainService = keychainService
    }
}
