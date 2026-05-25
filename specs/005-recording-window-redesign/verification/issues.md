# Verification Issues Registry: Recording Floating Window Redesign

**Feature**: 005-recording-window-redesign
**Date**: 2026-03-15
**Verification**: full re-run (--full)

## Resolved Issues

| ID | Severity | Task | Description | Status |
|---|---|---|---|---|
| V001 | critical | T025/T040 | Option+Shift+C/Option+Shift+V dead code - modifier check order | fixed |
| V002 | critical | T046 | MockPasteService - missing protocol methods | fixed |
| V003 | high | T043 | No fallback to non-streaming in stopRecording() | fixed |
| V004 | medium | T021 | Timer color .orange instead of #D94040 | fixed |
| V005 | medium | T035 | Hotkeys 1/2/3 - cyclic switching implemented | fixed |
| V006 | medium | T043 | Retry button without arrow.clockwise | fixed |
| V007 | low | T023 | hasAccessibility dead code | fixed |
| V008 | low | T028 | padding .bottom 8 -> 12 | fixed |
| V009 | low | T044 | ControlBarView without transition | fixed |
| V010 | high | T043 | retryFromError() - V003 regression, streaming without fallback | fixed |

## Open Issues

### V011 [low] - No hover effect on ControlBarView buttons

- **Task**: T013
- **File**: `Verborra/Views/ControlBarView.swift`
- **Type**: missing_visual_behavior
- **Description**: The contract specifies hover color `#D0D0D0` for buttons, but `.onHover` is not implemented. `.buttonStyle(.plain)` removes the default AppKit hover.
- **Severity**: low (cosmetic)
- **Status**: detected
