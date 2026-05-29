# Contract — Diagnostic event: first-voice-turn language resolution

**Feature**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md)

This contract specifies the new structured `DiagnosticLogger` event emitted on the first voice turn of a chat session.

---

## When the event fires

Exactly once per chat session, at the formatting-stage submission site inside `RecordingViewModel.streamChat()`, when the captured-local `isFirstVoiceTurn` is `true`.

- Fires **after** `resolvedTargetLanguage` and `overrideSource` are computed.
- Fires **before** the network call to the LLM (so a failed call still produces the event — important for triaging "wrong language" reports).
- Does **not** fire on continuation turns of the same chat session.
- Does **not** fire on text-only / non-voice submission paths.

## Log call shape

Using the existing `DiagnosticLogger` API:

```swift
log.info(
    "Language resolution for first voice turn",
    metadata: [
        "resolvedTargetLanguage": resolvedTarget.rawValue,
        "directiveInjected": "true",
        "overrideSource": overrideSource,           // "settings-default" | "user-changed"
        "isFirstVoiceTurn": "true"
    ]
)
```

- **Logger instance**: the existing `private let log = DiagnosticLogger.logger(for: .api)` — co-located with the formatting-stage code. If `RecordingViewModel` doesn't currently hold an `.api` logger, add one alongside the existing `FlowTracker` / `.userAction` usage. Reusing `.api` is preferred over `.userAction` here because the event describes a *prompt-assembly* fact, not a user input event.
- **Level**: `INFO`.
- **Message text**: human-readable, fixed. The structured payload is the metadata dict.

## JSONL on-disk shape

Following the existing `JSONLFileWriter` format used by `ChatSession`:

```json
{
  "timestamp": "2026-05-28T12:34:56.789Z",
  "level": "INFO",
  "category": "api",
  "message": "Language resolution for first voice turn",
  "metadata": {
    "resolvedTargetLanguage": "fr",
    "directiveInjected": "true",
    "overrideSource": "user-changed",
    "isFirstVoiceTurn": "true"
  }
}
```

## Metadata field schema

| Field                     | Type           | Values                                                          | Required |
|---------------------------|----------------|-----------------------------------------------------------------|----------|
| `resolvedTargetLanguage`  | String         | `SupportedLanguage.rawValue` (e.g. `"en"`, `"ru"`, `"fr"`, …)   | yes      |
| `directiveInjected`       | String         | `"true"` (always — event only fires when injection happens)     | yes      |
| `overrideSource`          | String (enum)  | `"settings-default"` (user did not change the picker since open) \| `"user-changed"` (user changed the picker between open and submit) | yes      |
| `isFirstVoiceTurn`        | String         | `"true"` (always — event only fires for first turn)             | yes      |

All values are `String` because the existing `DiagnosticLogger.metadata` parameter type is `[String: String]?`. Future widening to typed values (Bool / enum) is a logging-infrastructure decision outside this feature's scope.

## Privacy and security (Principle 4)

This event MUST NOT contain:

- The transcribed text (output of stage 1).
- The formatted output (LLM response).
- The OpenAI API key or any header containing it.
- The user's source-language audio.

All four metadata fields are either small enum values or boolean strings — no PII, no message content. The constitution's privacy clause is satisfied without needing `\(value, privacy: .private)` wrapping.

## Expected volume

- One event per chat session start.
- Typical user: <50 events per day.
- Log file rotation (hourly, 24 h retention per constitution Principle 6) handles volume without configuration changes.

## Backwards compatibility

This is a new event with new metadata fields. It does not modify any existing event. Downstream log readers that aren't aware of it will ignore unknown fields per JSONL convention.
