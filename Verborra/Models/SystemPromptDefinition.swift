import Foundation

// MARK: - SystemPromptDefinition (T039)

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
    static let simpleVoiceToText = SystemPromptDefinition(
        id: "simple-voice-to-text",
        translations: [
            .en: (
                name: "Simple Voice To Text",
                content: "Fix speech recognition errors, add punctuation and capitalization. Break into paragraphs by meaning. Return only the corrected text."
            ),
            .ru: (
                name: "Речь в текст",
                content: "Исправь ошибки распознавания речи, расставь знаки препинания и заглавные буквы. Разбей на абзацы по смыслу. Верни только исправленный текст."
            ),
            .es: (
                name: "Voz a texto",
                content: "Corrige los errores de reconocimiento de voz, añade puntuación y mayúsculas. Divide en párrafos por significado. Devuelve solo el texto corregido."
            ),
            .fr: (
                name: "Voix en texte",
                content: "Corrige les erreurs de reconnaissance vocale, ajoute la ponctuation et les majuscules. Découpe en paragraphes par sens. Renvoie uniquement le texte corrigé."
            ),
            .de: (
                name: "Sprache zu Text",
                content: "Korrigiere Spracherkennungsfehler, füge Zeichensetzung und Großschreibung hinzu. Unterteile in Absätze nach Bedeutung. Gib nur den korrigierten Text zurück."
            ),
            .pt: (
                name: "Voz para texto",
                content: "Corrija os erros de reconhecimento de voz, adicione pontuação e maiúsculas. Divida em parágrafos por significado. Retorne apenas o texto corrigido."
            ),
            .zh: (
                name: "语音转文字",
                content: "修正语音识别错误，添加标点符号和大写字母。按意义分段。仅返回修正后的文本。"
            ),
            .ja: (
                name: "音声テキスト変換",
                content: "音声認識の誤りを修正し、句読点と大文字を追加してください。意味ごとに段落に分けてください。修正されたテキストのみを返してください。"
            ),
            .ko: (
                name: "음성을 텍스트로",
                content: "음성 인식 오류를 수정하고 구두점과 대문자를 추가하세요. 의미별로 단락을 나누세요. 수정된 텍스트만 반환하세요."
            ),
            .it: (
                name: "Voce in testo",
                content: "Correggi gli errori di riconoscimento vocale, aggiungi punteggiatura e maiuscole. Dividi in paragrafi per significato. Restituisci solo il testo corretto."
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
