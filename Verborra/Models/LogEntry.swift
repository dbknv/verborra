import Foundation

// MARK: - LogEntry (T004)

/// Одна запись лога. Сериализуется в JSONL (FR-009, FR-019).
struct LogEntry: Codable, Sendable {
    let timestamp: String
    let level: String
    let category: String
    let sessionId: String
    let message: String
    let metadata: [String: String]?
    let error: ErrorContext?

    /// Создаёт LogEntry с текущим временем в ISO 8601 с миллисекундами и часовым поясом (FR-018).
    init(
        level: LogLevel,
        category: LogCategory,
        sessionId: String,
        message: String,
        metadata: [String: String]? = nil,
        error: ErrorContext? = nil
    ) {
        self.timestamp = Self.timestampFormatter.string(from: Date())
        self.level = level.displayName
        self.category = category.rawValue
        self.sessionId = sessionId
        self.message = message
        self.metadata = metadata
        self.error = error
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - ErrorContext (T005)

/// Контекст ошибки для самодостаточной диагностики (FR-010).
struct ErrorContext: Codable, Sendable {
    let description: String
    let method: String
    let parameters: [String: String]?
    let errorCode: String?
    let state: AppState?
    let breadcrumbs: [Breadcrumb]
}

// MARK: - AppState (T006)

/// Снимок состояния приложения на момент ошибки.
struct AppState: Codable, Sendable {
    let activeDevice: String?
    let recordingStatus: String
    let recordingDuration: Double?
    let currentOperation: String?
}

// MARK: - Breadcrumb (T007)

/// Один шаг в цепочке действий (элемент ring buffer, capacity 20).
struct Breadcrumb: Codable, Sendable {
    let timestamp: String
    let label: String
    let category: String
    let metadata: [String: String]?

    init(label: String, category: LogCategory, metadata: [String: String]? = nil) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = formatter.string(from: Date())
        self.label = label
        self.category = category.rawValue
        self.metadata = metadata
    }

    // For testing / deserialization
    init(timestamp: String, label: String, category: String, metadata: [String: String]? = nil) {
        self.timestamp = timestamp
        self.label = label
        self.category = category
        self.metadata = metadata
    }
}
