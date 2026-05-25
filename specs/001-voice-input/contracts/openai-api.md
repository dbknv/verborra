# API Contracts: OpenAI API

**Feature**: 001-voice-input
**Date**: 2026-03-04
**Updated**: 2026-03-05

---

## 1. Audio Transcriptions API — Audio Transcription

### Request

```
POST https://api.openai.com/v1/audio/transcriptions
Content-Type: multipart/form-data; boundary={boundary}
Authorization: Bearer {API_KEY}
```

**Multipart fields:**

| Field | Type | Required | Description |
|---|---|---|---|
| `file` | binary | Yes | WAV data (PCM Int16, 16 kHz, mono) |
| `model` | string | Yes | One of: `gpt-4o-mini-transcribe` (default), `gpt-4o-transcribe`, `whisper-1` |
| `language` | string | No | ISO 639-1 code (`"ru"`, `"en"` etc.) — from the "voice language" setting |
| `response_format` | string | No | `json` (REQUIRED for compatibility across all models) |

### Response (200 OK)

```json
{
  "text": "Recognized text from audio."
}
```

### Model Compatibility

| Parameter | whisper-1 | gpt-4o-transcribe | gpt-4o-mini-transcribe |
|---|---|---|---|
| `response_format: json` | Yes | Yes | Yes |
| `response_format: text` | Yes | Yes | Yes |
| `response_format: srt/vtt/verbose_json` | Yes | No | No |
| `language` (ISO 639-1) | Yes | Yes | Yes |
| Streaming (SSE) | Non-incremental | Incremental | Incremental |

**Important**: the code MUST use `response_format: "json"` for compatibility with all models.

### Errors

| Code | Description | Handling |
|---|---|---|
| 400 | Invalid audio format | `RecordingError.transcriptionFailed` |
| 401 | Invalid API key | `RecordingError.apiKeyNotConfigured` |
| 413 | File > 25 MB | `RecordingError.fileSizeLimitReached` |
| 429 | Rate limit | Retry with exponential backoff (max 3 attempts) |
| 500+ | Server error | `RecordingError.transcriptionFailed` |

### Limits

- Maximum file size: 25 MB
- Supported formats: wav, mp3, m4a, flac, ogg, webm (+ opus, pcm16 for gpt-4o models)
- For 16 kHz mono WAV: ~1.92 MB/min → 25 MB ≈ 13 min

---

## 2. Chat Completions API — AI Formatting

### Request

```
POST https://api.openai.com/v1/chat/completions
Content-Type: application/json
Authorization: Bearer {API_KEY}
```

```json
{
  "model": "{selectedLLMModel from settings}",
  "messages": [
    {
      "role": "system",
      "content": "{content of the selected SystemPrompt}\n\nResponse language: {textLanguage}"
    },
    {
      "role": "user",
      "content": "{rawText from Audio Transcriptions API}"
    }
  ],
  "temperature": 0.2,
  "max_completion_tokens": 4000
}
```

**Available models:**

| Model | Price (input/output per 1M tokens) | Default |
|---|---|---|
| `gpt-4.1-nano` | $0.10 / $0.40 | Yes |
| `gpt-4o-mini` | $0.15 / $0.60 | |
| `gpt-4.1-mini` | $0.40 / $1.60 | |
| `gpt-5-nano` | $0.05 / $0.40 | |

### Response (200 OK)

```json
{
  "id": "chatcmpl-...",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "Formatted text with Markdown markup."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 100,
    "completion_tokens": 150,
    "total_tokens": 250
  }
}
```

### Errors

| Code | Description | Handling |
|---|---|---|
| 400 | Invalid request | `RecordingError.formattingFailed` |
| 401 | Invalid API key | `RecordingError.apiKeyNotConfigured` |
| 429 | Rate limit | Retry with exponential backoff (max 3 attempts) |
| 500+ | Server error | `RecordingError.formattingFailed` |

### Default System Prompt

```
Fix punctuation, place paragraphs, and add Markdown formatting
(headings, lists, emphasis). Return only the corrected text
without explanations.
```

---

## 3. API Key Validation — Key Verification

### Request

Test request for validating the API key when saving in settings (FR-011b).

```
GET https://api.openai.com/v1/models
Authorization: Bearer {API_KEY}
```

### Response (200 OK) — key is valid

```json
{
  "data": [...]
}
```

### Response (401) — key is invalid

```json
{
  "error": {
    "message": "Incorrect API key provided: sk-****.",
    "type": "invalid_request_error",
    "code": "invalid_api_key"
  }
}
```

---

## Common Contracts

### Authorization Headers

All requests to the OpenAI API MUST include:

```
Authorization: Bearer {apiKey}
```

Where `{apiKey}` is retrieved from the macOS Keychain.

### Retry Policy

| Parameter | Value |
|---|---|
| Maximum attempts | 3 |
| Initial delay | 1 second |
| Multiplier | 2x (exponential backoff) |
| Retry on | 429 (Rate Limit), 500+ (Server Error) |
| Do not retry on | 400, 401, 413 (client errors) |

### Timeout

| Request | Timeout |
|---|---|
| Transcription (Audio API) | 60 seconds |
| Formatting (Chat Completions) | 30 seconds |
| Key validation (Models API) | 10 seconds |
