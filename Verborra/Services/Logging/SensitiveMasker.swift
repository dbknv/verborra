import Foundation

// MARK: - SensitiveMasker (T008)

/// Маскирование конфиденциальных данных перед записью в JSONL (FR-011, FR-016).
enum SensitiveMasker {

    /// Маскирует API-ключ: `sk-...XXXX` (последние 4 символа).
    /// Короткие ключи (< 8 символов) → `***`.
    static func maskAPIKey(_ key: String) -> String {
        guard key.count >= 8 else { return "***" }
        let suffix = String(key.suffix(4))
        return "sk-...\(suffix)"
    }

    /// Маскирует распознанный текст: `[transcription:Nchars]` (только длина).
    static func maskTranscription(_ text: String) -> String {
        "[transcription:\(text.count)chars]"
    }

    /// Описывает аудиобуфер без содержимого — только метаданные.
    static func describeAudioBuffer(sampleCount: Int, format: String) -> String {
        "[audio:\(sampleCount)samples,\(format)]"
    }

    /// Маскирует заголовки запроса: убирает значения Authorization и Bearer-токены.
    static func maskHeaders(_ headers: [String: String]) -> [String: String] {
        var masked = headers
        for (key, value) in masked {
            let lowered = key.lowercased()
            if lowered == "authorization" || lowered == "x-api-key" {
                if value.contains("sk-") || value.contains("Bearer") {
                    masked[key] = "Bearer \(maskAPIKey(value.replacingOccurrences(of: "Bearer ", with: "")))"
                } else {
                    masked[key] = "***"
                }
            }
        }
        return masked
    }
}
