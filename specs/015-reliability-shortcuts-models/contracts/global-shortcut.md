# Contract: Global Shortcut, Recorder and Fn Support (US3)

**Requirements**: FR-014…FR-022, FR-028 | **Research**: R14–R16 | **Model**: [data-model.md §2](../data-model.md#2-global-shortcut-us3)

## Service interface

```swift
@MainActor
protocol GlobalHotkeyServiceProtocol: AnyObject {
    var shortcut: GlobalShortcut { get }
    var status: HotkeyRegistrationStatus { get }      // observable
    var isPaused: Bool { get set }                    // true while the recorder captures
    func start(onToggle: @escaping @MainActor () -> Void)
    func validate(_ candidate: GlobalShortcut) -> ShortcutValidationResult
    func apply(_ candidate: GlobalShortcut) -> ShortcutValidationResult   // validate → persist → re-register → log
    func resetToDefault()
    func stop()
}
```

## Registration

| `shortcut.modifiers.contains(.fn)` | Mechanism | Permission | Setup |
|---|---|---|---|
| no | Carbon via KeyboardShortcuts | none | `KeyboardShortcuts.setShortcut(.init(carbonKeyCode:carbonModifiers:), for: .toggleOverlay)`; `onKeyDown` → `onToggle` on main |
| yes | `FnEventTap` | Accessibility | `KeyboardShortcuts.setShortcut(nil, …)`; create the tap on a dedicated `Thread` with its own `CFRunLoop` |

`FnEventTap` contract:

- `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: keyDown|flagsChanged)`.
- The callback runs on the tap thread. It feeds `FnTracker`. On keyDown that matches `shortcut` (keyCode equal, effective modifiers equal, not autorepeat) it returns `nil` (the event is swallowed) and does `DispatchQueue.main.async(onToggle)`. Every other event is returned unchanged.
- `tapDisabledByTimeout` / `tapDisabledByUserInput` → `CGEvent.tapEnable(tap:enable:true)` and log INFO `Event tap re-enabled` (`reason`, category `.hotkey`).
- `isPaused == true` → events pass through unmatched.
- `tapCreate` returns nil → `status = .needsAccessibility` if `!AXIsProcessTrusted()`, else `.failed`. The tap is retried when `PermissionManager` reports that Accessibility was granted.
- **Privacy**: the tap never logs or stores key codes or characters of non-matching events.

Changing the shortcut tears down the old mechanism before setting up the new one. At no point are two mechanisms active.

## Recorder field (`ShortcutRecorderField`)

| Situation | Field shows |
|---|---|
| Not focused | The current shortcut, e.g. `🌐︎ ⌥ Space`, via `ShortcutFormatter` |
| Focused, nothing held | Placeholder "Press shortcut…" |
| Focused, modifiers held | The held modifiers in order, e.g. `⌥ ⇧` (updated on every `flagsChanged`) |
| Regular key without a modifier | Placeholder plus hint "Add at least one modifier: 🌐︎ ⌃ ⌥ ⇧ ⌘" |
| Rejected | The previous shortcut plus a warning (below) |

Next to it: a **Reset to default** button (⌥Space). Below it: the status line (`needsAccessibility` → "🌐︎ shortcuts need Accessibility access", with a button that opens the permission; `failed` → the message).

Focus behaviour: clicking the field makes it first responder and sets `isPaused = true`. Saving, Esc, a rejection or losing focus resigns it and sets `isPaused = false`.

## Validation order (first match wins)

| # | Rule | Rejection | Warning text (en) |
|---|---|---|---|
| 1 | `modifiers.isEmpty` | `modifierRequired` | "Add at least one modifier (🌐︎ ⌃ ⌥ ⇧ ⌘)." |
| 2 | keyCode ∈ {53 Esc, 18 "1", 19 "2", 20 "3"} with modifiers ⊆ {fn, shift}; or (keyCode ∈ {8 C, 9 V}, modifiers ∈ {⌥, ⌥⇧}); or ⌘W | `conflictsWithOverlay` | "This shortcut is used inside the Verborra window." |
| 3 | ⌘Q, ⌘, | `reservedByApp` | "This shortcut is used by Verborra's menu." |
| 4 | Matches an enabled entry of `CopySymbolicHotKeys()` (Fn ignored for the comparison) | `reservedBySystem` | "This shortcut is reserved by macOS." |
| 5 | No Fn, and a trial `RegisterEventHotKey` fails with `eventHotKeyExistsErr` | `inUseByAnotherApp` | "This shortcut is already used by another app." |

## Display (`ShortcutFormatter`)

- Format: modifiers in the order 🌐︎ ⌃ ⌥ ⇧ ⌘, then the key name, **separated by single spaces**: `"🌐︎ ⌥ Space"`, `"⌘ ⇧ R"`, `"🌐︎ ⌃ F5"`.
- Key names: letters and digits in upper case; `Space`, `Return`, `Tab`, `Delete`, `⌦`, `←→↑↓`, `F1…F20`, `Home`, `End`, `PgUp`, `PgDn`. Other keys use the current keyboard layout's character (`UCKeyTranslate`).
- Used by: Settings recorder, `ControlBarView` Start/Stop hint (FR-028), menu hints.

## Logging (new category `.hotkey`)

- Accepted: INFO `Global shortcut changed` (`old`: `"⌥ Space"`, `new`: `"🌐︎ ⌥ Space"`, `mechanism`: `carbon` / `eventTap`) (FR-022).
- Rejected: INFO `Global shortcut rejected` (`candidate`, `reason`).
- Registration failure: ERROR `Global shortcut registration failed` (`shortcut`, `mechanism`, `error`).
- The hotkey firing stays INFO `Hotkey triggered` (`.userAction`), plus `mechanism`.
