# Data Model: Vocabularies and Personal Preferences (012-vocabularies)

**Date**: 2026-03-22
**Branch**: `012-vocabularies`

## Entities

### VocabularyEntry

A vocabulary entry: a target word and a set of alternative spellings.

| Field | Type | Description | Constraints |
|------|-----|----------|-------------|
| `id` | `UUID` | Unique entry identifier | Generated automatically at creation |
| `targetWord` | `String` | Target word/phrase/URL | Not empty; unique among all entries |
| `alternatives` | `[String]` | Alternative spellings | At least 1 element; each is non-empty; none matches `targetWord` |
| `createdAt` | `Date` | Creation date | Set at creation; used for sorting (newest at the bottom) |

**Protocols**: `Codable`, `Identifiable`, `Equatable`

**Validation**:
- `targetWord.trimmingCharacters(in: .whitespacesAndNewlines)` must not be empty.
- `alternatives` must not contain empty strings (after trim).
- `alternatives` must not contain a string matching `targetWord` (case-sensitive).
- `targetWord` must be unique among all entries in `VocabularyStore`.

**Lifecycle**:
```
Create (Add) → Persist (JSON) → Update → Delete
                                ↑                    |
                                └────────────────────┘
```

### PersonalPreferences

A single text value — stored in `@AppStorage`.

| Field | Type | Description | Constraints |
|------|-----|----------|-------------|
| `personalPreferencesText` | `String` | Arbitrary text with Markdown markup | Empty string = no preferences set; no length limit |

**Storage**: `UserDefaults` via `@AppStorage("personalPreferencesText")` in `AppSettings`.

## Relationships

```
VocabularyStore (1) ──── contains ──── (*) VocabularyEntry
                                              │
                                              ├── targetWord (1)
                                              └── alternatives (1..*)

AppSettings (1) ──── contains ──── (1) personalPreferencesText

PromptEnhancer ──── reads ──── VocabularyStore.entries
               ──── reads ──── AppSettings.personalPreferencesText
               ──── builds ──── fullSystemPrompt
```

## Storage

### vocabularies.json

**Location**: `~/Library/Application Support/Verborra/vocabularies.json`

**Format**:
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "targetWord": "GitHub",
    "alternatives": ["git hub", "githab"],
    "createdAt": "2026-03-22T10:30:00Z"
  },
  {
    "id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "targetWord": "https://meet.google.com/abc-def",
    "alternatives": ["meeting link", "meet link"],
    "createdAt": "2026-03-22T10:31:00Z"
  }
]
```

### personalPreferencesText (UserDefaults)

**Key**: `personalPreferencesText`
**Type**: `String`
**Default**: `""` (empty string)

## Indexes and search

- `targetWord` uniqueness check runs as a linear scan over the array (up to 100 entries — O(n) is acceptable).
- Alternative uniqueness across all entries — a double loop O(n*m), acceptable when n ≤ 100.
- Card sorting by `createdAt` (ascending) — stable, in the order of addition.
