# Contract: Floating Window Bottom Bar and Number Keys (US4)

**Requirements**: FR-023…FR-029, FR-043, FR-044, FR-052, FR-061, FR-020 (key scoping) | **Research**: R16, R17, R29, R32 | **Model**: [data-model.md §5](../data-model.md#5-session-selection-us4)

## Layout (pre-recording phase)

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ (no prompt header: removed)                                                  │
│                         … recording / waveform area …                        │
├──────────────────────────────────────────────────────────────────────────────┤
│ [🎤 MacBook Pro Mic  1] [💬 English  2] [❝ Speech To Text  3]   [▶ Start 🌐︎ ⌥ Space] [⇥ Exit Esc] │
└──────────────────────────────────────────────────────────────────────────────┘
```

| Position | Control | SF Symbol | Title | Hint | Menu items (order = cycle order) |
|---|---|---|---|---|---|
| 1 | Microphone menu | `mic.fill` | selected device name; width follows the name, no fixed cap; first to shrink when space runs out (R34) | `1` | title **Input device**, then System Default, divider, devices alphabetical |
| 2 | Output language menu | `text.bubble.fill` | language display name; width follows the name; last to shrink (R34) | `2` | title **Output language**, then `SupportedLanguage.allCases` |
| 3 | **Prompt menu (moved)** | `text.quote` | `PromptNameRule.display(selectedPrompt.name)`; button width follows the name, maximum = room left before the right group minus the normal gap (R34) | `3` | title **Using prompt**, then `promptsStore.prompts` in store order, ✓ on selected |
| right | Start/Stop/Cancel | `play.fill` / `stop.fill` / `xmark` | localized | `ShortcutFormatter(shortcut)` | n/a |
| right | Exit | existing | Exit | `Esc` | n/a |

**Height rule (FR-065, R35)**: in the pre-recording phase the window has a fixed height of 200 pt (content 155 + bottom bar 45) in every state; every pre-recording view fits without clipping.

**Width rule (FR-063, FR-064, R34)**: all three selector buttons size to their titles with no fixed cap. Left group and right group are separated by a spacer that never goes below the normal button gap. When the row is too narrow, the microphone title truncates first, then the prompt title, then the language ("…"); the right group never shrinks. Buttons never overlap.

All three menus use the existing `controlBarMenu` and `ControlBarButtonLabel` styling (FR-025). Each menu's items are wrapped in `Section(title)`, which macOS renders as a non-selectable title line plus a separator (FR-043, FR-044). The menus are enabled in `.idle`, `.recording` and `.error`, and disabled in `.starting` (including a microphone switch), `.transcribing` and `.formatting`. In the post-processing phase the bar shows Copy and Paste as today, without the prompt menu.

## Key handling

The local monitor only handles events whose `event.window` is the overlay panel. Events for other windows (Settings, onboarding) are returned untouched (FR-020).

| Key | keyCode | Allowed when | Action |
|---|---|---|---|
| 1 | 18 | `preProcessing` ∧ `state ∈ {idle, recording, error}` ∧ no modifiers | `cycleMicrophone()` (while recording, or in error after a failed switch, this starts a switch: [recording-start.md](./recording-start.md)) |
| 2 | 19 | same | `cycleTextLanguage()` |
| 3 | 20 | same | `cyclePrompt()` |
| Esc | 53 | always | `dismissOverlay()` (also cancels `.starting`) |
| others | n/a | unchanged from today (⌥C/⌥V/⌥⇧C/⌥⇧V/⌘W/Enter) | unchanged |

1, 2 and 3 do nothing in `.starting` (including a microphone switch), `.transcribing` and `.formatting` (AS 4.7, FR-052). Cycling reads the model lists, never the menu items, so a title is never selected.

## `cyclePrompt()` semantics

```text
prompts = promptsStore.prompts            # live, reflects Settings edits
if prompts.isEmpty → no-op
i = prompts.firstIndex(id == selectedPrompt.id)
if i == nil → changePrompt(promptsStore.defaultPrompt, source: .key)
else        → changePrompt(prompts[(i + 1) % prompts.count], source: .key)
```

`count == 1` selects the same prompt again: nothing visible changes and nothing breaks (AS 4.3).

`changePrompt(_:source:)` (shared by the menu and key 3): sets `selectedPrompt`, mirrors it into `chatSession?.systemPrompt`, and logs INFO `.userAction` `Prompt changed` (`from`, `to`, `source: key|menu`) (FR-029). It never writes to Settings, and the default prompt stays as configured (FR-027).

## Start/Stop hint

`ShortcutFormatter` output for the current `GlobalShortcut`, e.g. `🌐︎ ⌥ Space` (FR-028). It replaces the string-splitting `formattedShortcutLabel`.
