# Quickstart: App settings and onboarding

**Feature**: 002-app-settings-onboarding
**Updated**: 2026-03-07

## Prerequisites

- macOS 14+ (Sequoia)
- Xcode 16+ with Swift 5.9+
- OpenAI API key (for full testing)

## Build and run

```bash
# Switch to the branch
git checkout 002-app-settings-onboarding

# Build via SPM
swift build

# Or open in Xcode
open Package.swift
# Cmd+R to run
```

## Testing the onboarding

1. **Reset the onboarding flag** (for repeat testing):
   ```bash
   defaults delete com.apeek.Verborra onboardingCompleted
   ```

2. **Launch the app** — the onboarding window appears (active, focused, centered)

3. **Check the steps**:
   - Step 1 (Welcome): product description, only the "Next" button
   - Step 2 (Permissions): Accessibility and Microphone statuses, request buttons, descriptions. "Next" is active only after Microphone is granted
   - Step 3 (Mic Test): voice activity indicator while speaking
   - Step 4 (Completion): API key field + "Skip", hotkey display, "Finish" button

4. **Check navigation**: "Back" button on steps 2-4

5. **Check blocking**: during onboarding the "Settings..." menu item is disabled, the hotkey does not work

6. **Check that the window cannot be closed**: the close button is absent, Cmd+W does not work

## Testing the settings (6 tabs)

### "General" tab
- Audio device, duration, auto-record, permissions, launch at login
- **Verify absence**: overlay hotkey, API key, models (moved out)

### "Prompts" tab
- Prompt list, editor, languages
- **Verify absence**: STT/LLM models (moved to the LLM tab)

### "Hotkeys" tab (NEW)
- Overlay invocation hotkey (moved from General) — change it, verify it works
- Recording start/stop hotkey (NEW, default: Space) — change it, verify it works when the overlay is open
- **Check the conflict**: assign the same hotkey → warning

### "LLM" tab (NEW)
- OpenAI API key (moved from General) — enter it, verify validation
- STT model (moved from Prompts) — select one, verify recording
- LLM model (moved from Prompts) — select GPT 5.1/5.2/5.3, verify processing
- **Info popover**: click the (?) icon next to a model → description and price

### "About" tab
- Version, license, links

### "Advanced" tab
- "Reset onboarding" → restart notification (without a dialog)
- Restart → onboarding shown again

## Testing the settings window

1. **Sidebar** — 6 tabs, always visible, the collapse button is **absent**
2. **Inset from traffic lights** — the first sidebar item does not overlap the buttons
3. **No scrolling** — all elements of each tab are fully visible
4. **Cmd+W** — closes the settings window
5. **Cmd+Q** — quits the application
6. **Minimum size** — the window does not shrink below the threshold

## Testing the floating window

1. **Positioning**: horizontal center, 10% from the bottom edge of the screen
2. **Fixed size**: resize attempt does not work
3. **Controls**: prompt, language, settings — at the **bottom** of the window
4. **Recording hotkey**: Space (or a custom one) starts/stops recording
5. **Multi-monitor**: overlay on the screen with the active window

## Running tests

```bash
swift test
```

## Key files

| File | Purpose |
|------|---------|
| `Verborra/VerborraApp.swift` | Entry point, onboarding display |
| `Verborra/Models/AppSettings.swift` | Settings + recordingKeyCode |
| `Verborra/ViewModels/OnboardingViewModel.swift` | Onboarding logic |
| `Verborra/ViewModels/SettingsViewModel.swift` | Settings logic |
| `Verborra/Views/SettingsView.swift` | Settings (6 tabs) |
| `Verborra/Views/HotkeysSettingsTab.swift` | "Hotkeys" tab (NEW) |
| `Verborra/Views/LLMSettingsTab.swift` | "LLM" tab (NEW) |
| `Verborra/Views/OverlayPanel.swift` | Floating window (positioning) |
| `Verborra/Views/OverlayContentView.swift` | Overlay content (controls at the bottom) |
| `Verborra/Views/Onboarding/OnboardingWindow.swift` | Onboarding NSWindow |
