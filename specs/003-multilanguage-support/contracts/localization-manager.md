# Contract: LocalizationManager

**Date**: 2026-03-07

## Protocol

```swift
protocol LocalizationManagerProtocol: Observable {
    var currentLanguage: SupportedLanguage { get set }
    func string(_ key: String) -> String
    func string(_ key: String, args: CVarArg...) -> String
}
```

## Public interface of LocalizationManager

```swift
@Observable
final class LocalizationManager: LocalizationManagerProtocol {
    static let shared = LocalizationManager()

    /// Current interface language. On change — reloads the bundle.
    var currentLanguage: SupportedLanguage

    /// Returns the localized string for a key.
    /// Fallback: the English string, then the key itself.
    func string(_ key: String) -> String

    /// Returns the localized string with formatting.
    func string(_ key: String, args: CVarArg...) -> String

    /// Detects the language based on the OS preferences.
    /// Returns .en if the OS language is not supported.
    static func detectSystemLanguage() -> SupportedLanguage
}
```

## Behavior

### Initialization
1. Read `UserDefaults["uiLanguage"]`
2. If a value is present and valid -> use it
3. Otherwise -> call `detectSystemLanguage()`, save the result
4. Load the .lproj bundle for the selected language

### Language change
1. Set `currentLanguage = newValue`
2. Save into `UserDefaults["uiLanguage"]`
3. Load the new .lproj bundle
4. SwiftUI automatically re-renders all views (via @Observable)

### Fallback
1. Try to load the string from the currentLanguage bundle
2. If not found -> load from en.lproj (base)
3. If not found -> return the key as-is

## Integration with AppSettings

```swift
// Added to AppSettings:
@AppStorage("uiLanguage")
private var uiLanguageRawValue: String = ""

var uiLanguage: SupportedLanguage {
    get {
        if uiLanguageRawValue.isEmpty {
            return LocalizationManager.detectSystemLanguage()
        }
        return SupportedLanguage(rawValue: uiLanguageRawValue) ?? .en
    }
    set {
        uiLanguageRawValue = newValue.rawValue
        LocalizationManager.shared.currentLanguage = newValue
    }
}
```

## Integration with SwiftUI

```swift
// At the root of the application:
.environment(LocalizationManager.shared)

// In a View:
@Environment(LocalizationManager.self) private var l10n
Text(l10n.string("settings.general.recording"))
```
