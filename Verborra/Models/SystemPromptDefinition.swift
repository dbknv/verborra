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
                name: "Simple Voice To Text",
                content: "Fix spelling errors and add punctuation. Return only the corrected text."
            ),
            .ru: (
                name: "Речь в текст",
                content: "Исправь орфографические ошибки и расставь знаки препинания. Верни только исправленный текст."
            ),
            .es: (
                name: "Voz a texto",
                content: "Corrige los errores ortográficos y añade puntuación. Devuelve solo el texto corregido."
            ),
            .fr: (
                name: "Voix en texte",
                content: "Corrige les fautes d'orthographe et ajoute la ponctuation. Renvoie uniquement le texte corrigé."
            ),
            .de: (
                name: "Sprache zu Text",
                content: "Korrigiere Rechtschreibfehler und füge Satzzeichen ein. Gib nur den korrigierten Text zurück."
            ),
            .pt: (
                name: "Voz para texto",
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
                name: "Voce in testo",
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

// MARK: - DoNotAnswerInstruction (013)

/// Localized supplementary instruction injected into the system message when the
/// active prompt has `answerQuestionsInFirstMessage == false` AND the current
/// message is the first voice-transcribed turn of the chat session. Instructs the
/// LLM to skip answering and avoid clarifying questions, returning only the
/// formatted text. Language fallback mirrors `SystemPromptDefinition.content(for:)`.
enum DoNotAnswerInstruction {
    static let translations: [SupportedLanguage: String] = [
        .en: "Do not answer any questions found inside the user's text. Do not ask clarifying questions. Only format the text and return it as is.",
        .ru: "Не отвечай на вопросы, которые прозвучали внутри пользовательского текста. Не задавай уточняющих вопросов. Только отформатируй текст и верни его как есть.",
        .es: "No respondas a ninguna pregunta dentro del texto del usuario. No hagas preguntas aclaratorias. Solo formatea el texto y devuélvelo tal cual.",
        .fr: "Ne réponds à aucune question contenue dans le texte de l'utilisateur. Ne pose pas de questions de clarification. Formate uniquement le texte et renvoie-le tel quel.",
        .de: "Beantworte keine Fragen, die im Text des Benutzers vorkommen. Stelle keine klärenden Rückfragen. Formatiere den Text einfach und gib ihn unverändert zurück.",
        .pt: "Não respondas a perguntas dentro do texto do utilizador. Não faças perguntas de esclarecimento. Apenas formata o texto e devolve-o tal como está.",
        .zh: "不要回答用户文本中出现的任何问题。不要提出澄清问题。只对文本进行格式化并按原样返回。",
        .ja: "ユーザーのテキスト内にある質問には答えないでください。確認のための質問もしないでください。テキストをフォーマットしてそのまま返してください。",
        .ko: "사용자의 텍스트 안에 있는 질문에 답하지 마세요. 명확화를 위한 질문도 하지 마세요. 텍스트만 포맷팅하여 그대로 반환하세요.",
        .it: "Non rispondere a nessuna domanda all'interno del testo dell'utente. Non fare domande di chiarimento. Limita la tua azione a formattare il testo e restituirlo così com'è.",
    ]

    static func text(for language: SupportedLanguage) -> String {
        translations[language] ?? translations[.en]!
    }
}
