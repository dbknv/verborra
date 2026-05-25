import Foundation

// MARK: - SupportedLanguage (T011)

enum SupportedLanguage: String, Codable, CaseIterable {
    case en, ru, es, fr, de, pt, zh, ja, ko, it

    var displayName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .pt: return "Português"
        case .zh: return "中文"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .it: return "Italiano"
        }
    }

    var apiCode: String { rawValue }

    /// Returns language name localized to the given UI language (only .en and .ru supported as UI languages).
    func localizedDisplayName(for uiLanguage: SupportedLanguage) -> String {
        switch uiLanguage {
        case .ru:
            switch self {
            case .en: return "Английский"
            case .ru: return "Русский"
            case .es: return "Испанский"
            case .fr: return "Французский"
            case .de: return "Немецкий"
            case .pt: return "Португальский"
            case .zh: return "Китайский"
            case .ja: return "Японский"
            case .ko: return "Корейский"
            case .it: return "Итальянский"
            }
        default: // .en and any other
            switch self {
            case .en: return "English"
            case .ru: return "Russian"
            case .es: return "Spanish"
            case .fr: return "French"
            case .de: return "German"
            case .pt: return "Portuguese"
            case .zh: return "Chinese"
            case .ja: return "Japanese"
            case .ko: return "Korean"
            case .it: return "Italian"
            }
        }
    }
}
