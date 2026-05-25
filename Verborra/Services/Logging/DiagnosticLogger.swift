import Foundation
import os

// MARK: - AppStateProvider

/// Протокол для получения снимка состояния приложения (для ERROR-контекста).
protocol AppStateProvider: AnyObject, Sendable {
    func currentAppState() -> AppState
}

// MARK: - DiagnosticLogger (T013, T015)

/// Dual-sink фасад: os.Logger + JSONLFileWriter (FR-004).
/// Каждый сервис получает свой экземпляр через `DiagnosticLogger.logger(for:)`.
final class DiagnosticLogger: @unchecked Sendable {
    /// Session ID — единый для всего запуска приложения (FR-009).
    static let sessionId = UUID().uuidString

    /// Провайдер состояния приложения для ERROR-контекста (T036).
    static weak var appStateProvider: AppStateProvider?

    /// Функция для проверки текущего уровня логирования.
    /// Устанавливается при инициализации приложения.
    static var logLevelProvider: (() -> LogLevel) = { .info }

    /// Отложенное переключение в OFF при активной записи (T051).
    /// Если true — OFF откладывается до завершения.
    static var isRecordingActiveProvider: (() -> Bool) = { false }

    private let category: LogCategory
    private let osLogger: os.Logger

    private static let subsystem = "dev.apeek.verborra"

    private init(category: LogCategory) {
        self.category = category
        self.osLogger = os.Logger(subsystem: Self.subsystem, category: category.rawValue)
    }

    /// Фабричный метод — создаёт логгер для указанной категории.
    static func logger(for category: LogCategory) -> DiagnosticLogger {
        DiagnosticLogger(category: category)
    }

    // MARK: - Public API

    /// Логирует INFO-сообщение (FR-002).
    func info(_ message: String, metadata: [String: String]? = nil) {
        guard shouldLog(level: .info) else { return }
        let entry = LogEntry(
            level: .info,
            category: category,
            sessionId: Self.sessionId,
            message: message,
            metadata: metadata
        )
        osLogger.info("\(message, privacy: .public)")
        JSONLFileWriter.shared.write(entry: entry)
    }

    /// Логирует DEBUG-сообщение (FR-003).
    func debug(_ message: String, metadata: [String: String]? = nil) {
        guard shouldLog(level: .debug) else { return }
        let entry = LogEntry(
            level: .debug,
            category: category,
            sessionId: Self.sessionId,
            message: message,
            metadata: metadata
        )
        osLogger.debug("\(message, privacy: .public)")
        JSONLFileWriter.shared.write(entry: entry)
    }

    /// Логирует ERROR-сообщение с полным контекстом (FR-010).
    func error(
        _ message: String,
        method: String = #function,
        parameters: [String: String]? = nil,
        errorCode: String? = nil,
        flowId: UUID? = nil
    ) {
        guard shouldLog(level: .error) else { return }

        let breadcrumbs: [Breadcrumb]
        if let flowId {
            breadcrumbs = FlowTracker.shared.endFlow(flowId)
        } else {
            breadcrumbs = []
        }

        let errorContext = ErrorContext(
            description: message,
            method: method,
            parameters: parameters,
            errorCode: errorCode,
            state: Self.appStateProvider?.currentAppState(),
            breadcrumbs: breadcrumbs
        )

        let entry = LogEntry(
            level: .error,
            category: category,
            sessionId: Self.sessionId,
            message: message,
            error: errorContext
        )

        osLogger.error("\(message, privacy: .public)")
        JSONLFileWriter.shared.write(entry: entry)
    }

    // MARK: - Private

    private func shouldLog(level: LogLevel) -> Bool {
        let activeLevel = Self.logLevelProvider()

        // T051: Отложенное переключение в OFF при активной записи
        if activeLevel == .off && Self.isRecordingActiveProvider() {
            // Во время записи не отключаем — пишем как минимум ERROR
            return level == .error
        }

        return level.shouldLog(at: activeLevel)
    }
}
