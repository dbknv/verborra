# Contract: Login Item (US1)

**Requirements**: FR-001…FR-006 | **Research**: R1–R4 | **Model**: [data-model.md §1](../data-model.md#1-login-item-state-us1)

## Service interface

```swift
@MainActor
protocol LoginItemServiceProtocol: AnyObject {
    var status: LoginItemStatus { get }          // observable; mirrors SMAppService.mainApp.status
    var lastError: String? { get }
    var isRunningFromApplications: Bool { get }  // bundleURL under /Applications or ~/Applications
    func refresh()                                // re-read status (cheap, sync)
    func setEnabled(_ enabled: Bool)              // writes intent → register/unregister → refresh; logs
    func reconcileAtLaunch(onboardingCompleted: Bool)
    func openSystemSettings()                     // SMAppService.openSystemSettingsLoginItems()
}
```

`SettingsViewModel` and `OnboardingViewModel` call this protocol. They don't call `SMAppService` directly. Tests inject a fake that exposes a settable `status` and failure results for register/unregister.

## Startup reconcile

Called from `applicationDidFinishLaunching` after logging starts.

| `onboardingCompleted` | Intent (`nil` ⇒ on) | Status | Action | Log |
|---|---|---|---|---|
| false | any | any | none (the user hasn't been asked yet) | DEBUG |
| true | on | `.enabled` | none | INFO `Login item OK` |
| true | on | `.notRegistered` / `.notFound` | `register()` | INFO `Login item registered at launch` or ERROR `Login item register failed` (`status`, `error`) |
| true | on | `.requiresApproval` | none | INFO `Login item requires approval` |
| true | off | `.enabled` | set intent = on (the system is the truth) | INFO `Login item enabled externally` |
| true | off | other | none | DEBUG |

## UI contract: Settings › General › System

| Status | Toggle shows | Extra |
|---|---|---|
| `.enabled` | on | none |
| `.notRegistered` | off | none |
| `.requiresApproval` | off | caption "Verborra needs your approval in System Settings › Login Items." plus button **Open Login Items** |
| `.notFound` | off | caption with the error plus button **Open Login Items** |
| any, with `lastError` set | real status | red caption with `lastError` |
| any, with `isRunningFromApplications == false` | real status | caption "Verborra is running from <folder>. Move it to Applications so the right copy starts at login." |

Reconcile also writes one INFO `Login item reconcile` (`appPath`, `status`, `intent`, `action`) on every launch, so the log shows which copy was running.

Toggling: `setEnabled(newValue)`. While the call runs, the toggle shows the requested value. Afterwards it shows `status == .enabled` (it reverts on failure, AS 1.5). Status is refreshed in `.onAppear` and on `didBecomeActive`.

## UI contract: Onboarding › Completion

- Toggle "Start Verborra at login", **on by default**.
- When the user taps Finish (`completeOnboarding()`), `setEnabled(toggleValue)` runs before the window closes. If it fails, the error is shown inline and logged, and onboarding still completes. The user can change it later in Settings.
- Shown once: it isn't shown again once `onboardingCompleted == true`.

## Logging (new category `.loginItem`; SMAppService calls, per the constitution's "System calls")

`setEnabled` → INFO `Launch at login changed` (`old`, `new`, `statusBefore`, `statusAfter`). Failure → ERROR with `method`, `enabled`, `status`, and `error.localizedDescription`.

## Build and signing contract (FR-006)

- `project.pbxproj` (app target, Debug and Release): `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = "-"`, `DEVELOPMENT_TEAM = ""`, `ENABLE_HARDENED_RUNTIME = YES` (ad-hoc: the owner has no Apple certificate). `project.yml` matches. The entitlements file is unchanged.
- Release check: `codesign -dv /Applications/Verborra.app` must show `flags=0x10002(adhoc,runtime)`.
