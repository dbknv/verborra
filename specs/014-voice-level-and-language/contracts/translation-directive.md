# Contract — Translation directive (first voice turn only)

**Feature**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md)

This contract specifies the new `TranslateToTargetInstruction` enum: where it goes, what shape it has, and the literal text per supported language.

---

## Swift surface

```swift
// File: Verborra/Models/SystemPromptDefinition.swift
// Position: appended at the bottom of the file, parallel to `DoNotAnswerInstruction`.

enum TranslateToTargetInstruction {
    static let translations: [SupportedLanguage: String] = [
        // … entries below …
    ]

    static func text(for language: SupportedLanguage) -> String {
        translations[language] ?? translations[.en] ?? ""
    }
}
```

### Invariants

1. `translations` MUST have one entry per `SupportedLanguage` case covered by `DoNotAnswerInstruction.translations` (per VR-001 in [data-model.md](../data-model.md)).
2. Each value MUST be in the language it keys off — i.e. the Russian entry is in Russian, the German entry in German, etc.
3. Each value MUST contain both branches: "translate if different" AND "leave unchanged if already matches."
4. The directive MUST reference the *display name* of the target language (e.g. `"English"`, `"русский"`, `"Deutsch"`) — substitute the existing `SupportedLanguage.displayName` accessor.

---

## Per-language strings

Below are the literal directives. The placeholder `<TARGET>` is replaced with the target language's display name in that language (e.g. for `ru` → `"русский"`).

> **Convention**: each entry is a single paragraph wrapped under a Markdown heading (`## Response Language`) for parity with the existing prompt-section style produced by `PromptEnhancer`. The exact heading text MAY vary per language so the directive reads naturally; the body is what carries the instruction.

### English (`.en`)

```text
## Response Language

Return the final text in English. If the input is in another language, translate it to English. If the input is already in English, keep the language unchanged and only perform formatting and cleanup (do not retranslate or rephrase across languages).
```

### Russian (`.ru`)

```text
## Язык ответа

Верни итоговый текст на русском. Если входной текст на другом языке, переведи его на русский. Если входной текст уже на русском, не меняй язык и выполни только форматирование и очистку (не переводи и не перефразируй на другой язык).
```

### Spanish (`.es`)

```text
## Idioma de respuesta

Devuelve el texto final en español. Si la entrada está en otro idioma, tradúcela al español. Si la entrada ya está en español, no cambies el idioma y solo realiza formateo y limpieza (no traduzcas ni reformules entre idiomas).
```

### German (`.de`)

```text
## Antwortsprache

Gib den finalen Text auf Deutsch zurück. Wenn die Eingabe in einer anderen Sprache ist, übersetze sie ins Deutsche. Wenn die Eingabe bereits auf Deutsch ist, ändere die Sprache nicht und führe nur Formatierung und Bereinigung durch (nicht zwischen Sprachen übersetzen oder umformulieren).
```

### French (`.fr`)

```text
## Langue de réponse

Renvoie le texte final en français. Si l'entrée est dans une autre langue, traduis-la en français. Si l'entrée est déjà en français, ne change pas la langue et effectue uniquement la mise en forme et le nettoyage (ne traduis pas et ne reformule pas entre langues).
```

### Italian (`.it`)

```text
## Lingua della risposta

Restituisci il testo finale in italiano. Se l'input è in un'altra lingua, traducilo in italiano. Se l'input è già in italiano, non cambiare la lingua ed esegui solo formattazione e pulizia (non tradurre né riformulare tra lingue).
```

### Portuguese (`.pt`)

```text
## Idioma da resposta

Retorne o texto final em português. Se a entrada estiver em outro idioma, traduza-a para o português. Se a entrada já estiver em português, não altere o idioma e realize apenas formatação e limpeza (não traduza nem reformule entre idiomas).
```

### Dutch (`.nl`)

```text
## Antwoordtaal

Geef de uiteindelijke tekst terug in het Nederlands. Als de invoer in een andere taal is, vertaal die naar het Nederlands. Als de invoer al in het Nederlands is, verander de taal niet en voer alleen opmaak en opschoning uit (vertaal of herformuleer niet tussen talen).
```

### Polish (`.pl`)

```text
## Język odpowiedzi

Zwróć tekst końcowy po polsku. Jeśli wejście jest w innym języku, przetłumacz je na polski. Jeśli wejście jest już po polsku, nie zmieniaj języka i wykonaj tylko formatowanie i czyszczenie (nie tłumacz ani nie przeformułowuj między językami).
```

### Ukrainian (`.uk`)

```text
## Мова відповіді

Поверни підсумковий текст українською. Якщо вхідний текст іншою мовою, переклади його українською. Якщо вхідний текст уже українською, не змінюй мову й виконай лише форматування та очищення (не перекладай і не переформульовуй між мовами).
```

### Turkish (`.tr`)

```text
## Yanıt Dili

Nihai metni Türkçe olarak döndür. Giriş başka bir dildeyse Türkçeye çevir. Giriş zaten Türkçeyse dili değiştirme ve yalnızca biçimlendirme ve temizleme yap (diller arası çeviri veya yeniden ifadelendirme yapma).
```

> **Note**: the exact `SupportedLanguage` cases above mirror those listed in the existing `DoNotAnswerInstruction.translations` (per the implementation map). If the project's `SupportedLanguage` enum has additional cases at implementation time, add a corresponding entry; the validation test (VR-001) enforces full parity.

---

## Injection contract

- **When**: only when `isFirstVoiceTurn == true` at the formatting-stage submission site in `RecordingViewModel.streamChat()` (currently around line 615–628, alongside the existing `DoNotAnswerInstruction` injection).
- **What gets injected**: the result of `TranslateToTargetInstruction.text(for: resolvedTargetLanguage)`.
- **Where in the system message**: appended **before** the (optional) `DoNotAnswerInstruction` block, under its own `## Response Language` (or per-language equivalent) heading. The `PromptEnhancer`'s existing response-language section is **suppressed** on first voice turn to avoid duplicating the directive (the `PromptEnhancer` continues to add the section for all other paths, e.g. continuation turns going through `ChatSession.prepareMessagesForLLM`).
- **Order in the assembled system message** on first turn:
  1. Base dictation prompt from `systemPrompt.contentForLanguage(voiceLanguage)` (unchanged).
  2. **New**: `TranslateToTargetInstruction.text(for: resolvedTarget)`.
  3. Personal preferences / vocabulary replacements from `PromptEnhancer` (unchanged).
  4. (Conditional) `DoNotAnswerInstruction.text(for: voiceLanguage)` (unchanged behavior).
