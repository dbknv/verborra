# Contract — `AudioWaveformView` component (Direction 1)

**Feature**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md)

This contract specifies the updated public surface and internal behavior of the shared `AudioWaveformView` SwiftUI component.

---

## File

[Verborra/Views/Components/AudioWaveformView.swift](../../../Verborra/Views/Components/AudioWaveformView.swift)

## Public API (unchanged)

```swift
struct AudioWaveformView: View {
    let audioLevel: Float   // linear 0…1
    var body: some View { … }
}
```

- **Input**: `audioLevel: Float` in `[0.0, 1.0]`. Same field type, same range, same caller contract.
- **No new initializer parameters.** Per FR-008, call sites continue to work unchanged. This also means no `height:`, no `gain:`, no `barCount:` — the component owns these internally.

## Layout contract (new)

1. The component MUST render inside whatever vertical budget its parent assigns. It MUST NOT impose its own fixed height (the current `frame(height: 40)` style assumption inside the component, if any, is removed).
2. The component MUST use `GeometryReader` (or equivalent SwiftUI primitive) to read its container's `size.height` and compute bar heights as a fraction of that value.
3. The component MUST leave a small visual slack at the top of the container so the bars do not visually clip against the container edge during loud bursts. **Recommended slack**: `maxBarHeight = geometry.size.height * 0.9`.
4. The component's horizontal layout is unchanged from today (`N` bars distributed evenly across the available width).
5. If the parent does not assign a height (no `.frame(height:)` modifier on the parent), the component MUST still render without crashing or producing degenerate visuals; it MAY fall back to an intrinsic height (e.g. 24 pt) as a safety default.

## Amplitude contract (new)

1. The component MUST apply a non-linear amplitude curve before mapping `audioLevel` to bar height. **Specification**: `displayLevel = pow(audioLevel, 0.5)`.
2. At `audioLevel = 0.0`, every bar's height MUST be 0 (or a small intrinsic baseline; see "silence baseline" below).
3. At `audioLevel = 1.0`, the tallest bar's height MUST be `maxBarHeight` (i.e. ~90% of container height).
4. Intermediate values follow the square-root curve: e.g. `audioLevel = 0.10` → `displayLevel ≈ 0.32` → tallest bar ≈ 32% of `maxBarHeight`.
5. **Silence baseline**: the existing minimum-height behavior (small visible baseline so the indicator doesn't fully collapse) MAY be preserved for visual identity. If preserved, it MUST be no more than 10% of `maxBarHeight`.

## Smoothness contract (new)

1. The component MUST continue to animate transitions between consecutive `audioLevel` values using the existing 0.1 s `easeInOut` (or equivalent SwiftUI animation). No additional smoothing layer is required.
2. The component MUST NOT exhibit visible step artifacts at the 20 Hz audio-level publish rate. (Confirmed by the existing animation.)
3. The component MUST NOT flicker — bars MUST NOT visibly jump between two heights within a single `audioLevel` update interval. (Same animation guarantees this.)

## Per-bar variation (preserved)

The existing per-bar phase variation (`sin(Double(index) * 0.8 + level * 10) * 0.3 + 0.7`) is preserved. This keeps the indicator's visual identity unchanged (a textured row of bars rather than a uniform block).

## Call-site behavior

| Caller                                              | Current frame                  | Required change |
|-----------------------------------------------------|--------------------------------|-----------------|
| [RecordingView.swift:78](../../../Verborra/Views/RecordingView.swift#L78)              | no explicit frame              | **None** — component fills whatever vertical space the parent VStack assigns. Optionally wrap in `.frame(height: …)` if a specific height is desired in the floating window. |
| [InputFieldView.swift:29](../../../Verborra/Views/InputFieldView.swift#L29)            | `.frame(height: 24)`           | **None** — small container, indicator scales down automatically. |
| [MicrophoneTestStep.swift:20](../../../Verborra/Views/Onboarding/MicrophoneTestStep.swift#L20) | `.frame(height: 60)`           | **None** — larger container, indicator scales up automatically. |

## Negative tests

1. Passing `audioLevel = 0.0` for several seconds: bars sit at the silence baseline; no animation jitter.
2. Passing a level burst (instantaneous spike to `1.0` then back to `0.05`): bars saturate at `maxBarHeight`, smoothly decay through the curve back to ~22% (= `pow(0.05, 0.5)`).
3. Container height = 0 pt (degenerate): component does not crash; bars are clipped to 0 height (acceptable per FR-005).
4. Container height = 200 pt (oversize): bars scale up to use ~180 pt of vertical space; no visual artifacts.
