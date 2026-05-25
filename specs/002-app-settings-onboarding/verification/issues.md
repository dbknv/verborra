# Verification Issues Registry: 002-app-settings-onboarding

**Created**: 2026-03-05
**Last update**: 2026-03-05
**Verifier**: speckit.verify

---

## V001 — Incomplete Accessibility description on the permissions screen

| Field | Value |
|------|----------|
| **ID** | V001 |
| **Task** | T007 |
| **File** | `Verborra/Views/Onboarding/PermissionsStep.swift:24` |
| **Verification level** | L4 Deep |
| **Confidence** | 95% |
| **Required confidence** | 95% |
| **Severity** | medium |
| **Type** | missing_content |
| **Status** | fixed |

**Description**: The Accessibility description is incomplete. In the code: "Accessibility access is needed to automatically paste text into applications." The spec (FR-008a) additionally requires: "Without this permission, only copy-paste will be available. You can grant access later in app settings."

**Source of truth**: spec.md FR-008a — "for Accessibility — why the access is needed (auto-pasting text; without it only copy-paste is available; can be granted later in settings)"

**Fix context**:
- Automatic fix: yes
- Approach: Extend the Accessibility description string with the full text from the spec
- Affected files: `Verborra/Views/Onboarding/PermissionsStep.swift`
- Requires spec update: no

---

## V002 — No explicit "Skip" button for the API key on the completion screen

| Field | Value |
|------|----------|
| **ID** | V002 |
| **Task** | T008 |
| **File** | `Verborra/Views/Onboarding/CompletionStep.swift` |
| **Verification level** | L4 Deep |
| **Confidence** | 85% |
| **Required confidence** | 95% |
| **Severity** | low |
| **Type** | missing_ui_element |
| **Status** | fixed |

**Description**: FR-011 requires "an OpenAI API key input field with the option to skip ("Skip" / "Later" button)". In the current implementation there is no explicit "Skip" button next to the input field. The "Finish" button in the navigation bar lets the user skip the input, but this does not fully match the letter of the requirement.

**Source of truth**: spec.md FR-011

**Fix context**:
- Automatic fix: yes
- Approach: Add a hint text "Can be skipped — you can configure later" under the input field, or add an explicit "Skip" button
- Affected files: `Verborra/Views/Onboarding/CompletionStep.swift`
- Requires spec update: possibly (clarify the requirement)

---

## V003 — Dead code: resetting a non-existent onboardingCurrentStep key

| Field | Value |
|------|----------|
| **ID** | V003 |
| **Task** | T001 |
| **File** | `Verborra/ViewModels/SettingsViewModel.swift:170` |
| **Verification level** | L2 Standard |
| **Confidence** | 100% |
| **Required confidence** | 80% |
| **Severity** | low |
| **Type** | dead_code |
| **Status** | fixed |

**Description**: `SettingsViewModel.resetOnboarding()` contains the line `UserDefaults.standard.set(0, forKey: "onboardingCurrentStep")`, which resets a key that is no longer used in the application (T001 removed `@AppStorage("onboardingCurrentStep")`). It does not break functionality, but it is dead code.

**Source of truth**: tasks.md T001 — "remove @AppStorage(\"onboardingCurrentStep\")"

**Fix context**:
- Automatic fix: yes
- Approach: Remove the line `UserDefaults.standard.set(0, forKey: "onboardingCurrentStep")`
- Affected files: `Verborra/ViewModels/SettingsViewModel.swift`
- Requires spec update: no
