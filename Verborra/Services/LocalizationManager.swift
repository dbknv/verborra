import Foundation

// MARK: - LocalizationManagerProtocol

protocol LocalizationManagerProtocol: AnyObject {
    var currentLanguage: SupportedLanguage { get set }
    func string(_ key: String) -> String
    func string(_ key: String, args: CVarArg...) -> String
}

// MARK: - LocalizationManager

@Observable
final class LocalizationManager: LocalizationManagerProtocol {
    static let shared = LocalizationManager()

    private let log = DiagnosticLogger.logger(for: .settings)

    var currentLanguage: SupportedLanguage {
        didSet {
            guard currentLanguage != oldValue else { return }
            log.info("UI language changed", metadata: [
                "from": oldValue.rawValue,
                "to": currentLanguage.rawValue
            ])
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "uiLanguage")
            loadBundle(for: currentLanguage)
        }
    }

    private var currentBundle: Bundle = .main
    private var fallbackBundle: Bundle = .main

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "uiLanguage"),
           let language = SupportedLanguage(rawValue: saved) {
            self.currentLanguage = language
        } else {
            let detected = Self.detectSystemLanguage()
            self.currentLanguage = detected
            UserDefaults.standard.set(detected.rawValue, forKey: "uiLanguage")
        }

        if let enPath = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let enBundle = Bundle(path: enPath) {
            fallbackBundle = enBundle
        }

        loadBundle(for: currentLanguage)
    }

    // Test-only initializer
    init(language: SupportedLanguage, bundle: Bundle = .main) {
        self.currentLanguage = language
        self.currentBundle = bundle
        self.fallbackBundle = bundle
    }

    func string(_ key: String) -> String {
        let value = currentBundle.localizedString(forKey: key, value: nil, table: nil)
        if value != key { return value }

        let fallbackValue = fallbackBundle.localizedString(forKey: key, value: nil, table: nil)
        if fallbackValue != key { return fallbackValue }

        return key
    }

    func string(_ key: String, args: CVarArg...) -> String {
        let format = string(key)
        return String(format: format, arguments: args)
    }

    static func detectSystemLanguage() -> SupportedLanguage {
        let preferred = Locale.preferredLanguages
        for languageCode in preferred {
            let code = Locale(identifier: languageCode).language.languageCode?.identifier ?? ""
            if let lang = SupportedLanguage(rawValue: code), isUILanguage(lang) {
                return lang
            }
        }
        return .en
    }

    /// Only en and ru are supported as UI languages
    static func isUILanguage(_ language: SupportedLanguage) -> Bool {
        language == .en || language == .ru
    }

    private func loadBundle(for language: SupportedLanguage) {
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            currentBundle = bundle
        } else {
            currentBundle = fallbackBundle
        }
    }
}
