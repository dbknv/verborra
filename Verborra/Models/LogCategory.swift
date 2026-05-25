import Foundation

// MARK: - LogCategory

/// Категория модуля для фильтрации в Console.app и JSONL (FR-013).
enum LogCategory: String, Codable, CaseIterable, Sendable {
    case audio        // AudioCaptureService — устройства, выбор
    case bluetooth    // AudioCaptureService — Bluetooth-специфичные события
    case engine       // AudioCaptureService — AVAudioEngine lifecycle
    case tap          // AudioCaptureService — input node tap
    case stream       // AudioCaptureService — аудиопотоки, форматы
    case api          // TranscriptionService, FormattingService, ProcessingRouter
    case permissions  // PermissionManager
    case userAction   // RecordingViewModel, HotkeyService
    case lifecycle    // VerborraApp (AppDelegate)
    case settings     // SettingsViewModel, AppSettings
    case system       // PasteService, TargetAppTracker, AutostartService
    case vocabulary   // VocabularyStore, PromptEnhancer, PersonalPreferences
}
