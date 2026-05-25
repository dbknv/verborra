import Foundation

// MARK: - LogLevel

/// Режим логирования приложения (FR-001).
/// OFF — отключено, ERROR — только ошибки, INFO — ошибки + ключевые события, DEBUG — всё.
enum LogLevel: Int, Codable, CaseIterable, Comparable, Sendable {
    case off = 0
    case error = 1
    case info = 2
    case debug = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Проверяет, должно ли сообщение данного уровня быть записано при текущем активном уровне.
    /// Например, `.error.shouldLog(at: .info)` → true (ERROR пишется при INFO).
    func shouldLog(at activeLevel: LogLevel) -> Bool {
        guard activeLevel != .off else { return false }
        return self <= activeLevel
    }

    var displayName: String {
        switch self {
        case .off: "OFF"
        case .error: "ERROR"
        case .info: "INFO"
        case .debug: "DEBUG"
        }
    }
}
