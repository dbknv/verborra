# Contract: OpenAI Requests per Model

**Requirements**: FR-032, FR-033, FR-035, FR-040 | **Research**: R20–R23

## Chat Completions (`POST /v1/chat/completions`)

Built in two places, which MUST stay identical in shape: `FormattingService.format(...)` and `StreamingFormattingService.buildRequest(...)`.

```jsonc
{
  "model": "<LLMModel.rawValue>",
  "messages": [ ... ],                 // unchanged
  "max_completion_tokens": 4000,       // unchanged
  "temperature": 0.2,                  // ONLY if model.supportsTemperature
  "reasoning_effort": "none" | "low",  // ONLY if model.reasoningEffort != nil
  "stream": true                       // streaming service only, unchanged
}
```

| Model | `temperature` | `reasoning_effort` |
|---|---|---|
| gpt-5.2, gpt-5.4, gpt-5.5 | 0.2 (unless the probe flips it, R21) | — (unless the probe sets its lowest supported effort, R20) |
| gpt-5.4-mini | — | — (unless the probe sets its lowest supported effort, R20) |
| gpt-5.6-terra, gpt-5.6-sol, gpt-6-luna, gpt-6-sol | — | `none` |
| gpt-6.1-sol, gpt-6-astra | — | `low` |

The DEBUG request log adds `"reasoningEffort": "<value>|omitted"` next to the existing `temperature` field.

## Transcriptions (`POST /v1/audio/transcriptions`, multipart)

| Field | gpt-transcribe |
|---|---|
| `file` | `audio.wav`, unchanged |
| `model` | `gpt-transcribe` |
| `languages[]` | `<SupportedLanguage.apiCode>` when a recognition language is chosen; omitted for "auto" |
| `language` | **never sent** |
| `response_format` | `json` |

Response: `{ "text": "...", "languages": [{ "code": "ru" }] }`. Only `text` is read, and the parser is unchanged. An empty `text` still maps to `silenceDetected`.

## Error mapping (both services)

| HTTP | Body `error.code` | Result |
|---|---|---|
| 404 | any | `RecordingError.modelUnavailable(modelName: displayName, kind:)` |
| 400 / 403 | `model_not_found`, `model_not_available` | `RecordingError.modelUnavailable(...)` |
| 400 | other | unchanged (`transcriptionFailed` / `formattingFailed` with the body) |
| 401, 413, 429, 5xx | — | unchanged |

`modelUnavailable` is never retried and never falls back to another model. It is logged at ERROR in the `.api` category with `method`, `model` (raw ID), `status`, `message` (OpenAI's `error.message`, first 500 chars) and `errorCode`.

User-facing text:

| Key | en | ru |
|---|---|---|
| `error.modelUnavailable.text` | `%@ isn't available for your OpenAI account. Choose another text model in Settings.` | `Модель %@ недоступна для вашего аккаунта OpenAI. Выберите другую текстовую модель в настройках.` |
| `error.modelUnavailable.stt` | `%@ isn't available for your OpenAI account.` | `Модель %@ недоступна для вашего аккаунта OpenAI.` |
