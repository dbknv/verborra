import Foundation

// MARK: - SystemPromptDefinition (T039, 013-simplified)

struct SystemPromptDefinition {
    let id: String
    let translations: [SupportedLanguage: (name: String, content: String)]

    func name(for language: SupportedLanguage) -> String {
        translations[language]?.name ?? translations[.en]!.name
    }

    func content(for language: SupportedLanguage) -> String {
        translations[language]?.content ?? translations[.en]!.content
    }
}

// MARK: - Built-in Definitions

extension SystemPromptDefinition {
    /// Simplified in 013: content now asks the model ONLY to fix spelling and
    /// add punctuation, without paragraph splitting or rephrasing. The prompt
    /// itself is read-only in UI (see `SystemPrompt.isReadOnly`).
    static let simpleVoiceToText = SystemPromptDefinition(
        id: "simple-voice-to-text",
        translations: [
            .en: (
                name: "Speech To Text",
                content: "Fix spelling errors and add punctuation. Return only the corrected text."
            ),
            .ru: (
                name: "Речь в текст",
                content: "Исправь орфографические ошибки и расставь знаки препинания. Верни только исправленный текст."
            ),
            .es: (
                name: "Habla a texto",
                content: "Corrige los errores ortográficos y añade puntuación. Devuelve solo el texto corregido."
            ),
            .fr: (
                name: "Parole en texte",
                content: "Corrige les fautes d'orthographe et ajoute la ponctuation. Renvoie uniquement le texte corrigé."
            ),
            .de: (
                name: "Sprache zu Text",
                content: "Korrigiere Rechtschreibfehler und füge Satzzeichen ein. Gib nur den korrigierten Text zurück."
            ),
            .pt: (
                name: "Fala para texto",
                content: "Corrija os erros de ortografia e adicione a pontuação. Devolva apenas o texto corrigido."
            ),
            .zh: (
                name: "语音转文字",
                content: "纠正拼写错误并添加标点符号。仅返回修正后的文本。"
            ),
            .ja: (
                name: "音声テキスト変換",
                content: "スペルミスを修正し、句読点を追加してください。修正されたテキストのみを返してください。"
            ),
            .ko: (
                name: "음성을 텍스트로",
                content: "맞춤법 오류를 수정하고 구두점을 추가하세요. 수정된 텍스트만 반환하세요."
            ),
            .it: (
                name: "Parlato in testo",
                content: "Correggi gli errori di ortografia e aggiungi la punteggiatura. Restituisci solo il testo corretto."
            ),
        ]
    )
}

// MARK: - SystemPromptRegistry

enum SystemPromptRegistry {
    static let all: [SystemPromptDefinition] = [.simpleVoiceToText]

    static func definition(for systemId: String) -> SystemPromptDefinition? {
        all.first { $0.id == systemId }
    }
}

// MARK: - Note
//
// `DoNotAnswerInstruction` and `TranslateToTargetInstruction` previously lived
// in this file. As of the 014 refactor they belong to the system-prompt
// assembly layer and are co-located with `SystemPromptBuilder` in
// `Verborra/Services/PromptEnhancer.swift` (file kept under that legacy name
// for build-system reasons — the type inside is `SystemPromptBuilder`).
