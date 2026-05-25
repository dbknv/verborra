import Foundation

// MARK: - MaxRecordingDuration

enum MaxRecordingDuration: Int, Codable, CaseIterable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case twentyMinutes = 1200
    case sixtyMinutes = 3600

    var displayName: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .oneMinute: return l10n.string("common.duration.1min")
        case .fiveMinutes: return l10n.string("common.duration.5min")
        case .tenMinutes: return l10n.string("common.duration.10min")
        case .twentyMinutes: return l10n.string("common.duration.20min")
        case .sixtyMinutes: return l10n.string("common.duration.60min")
        }
    }

    var timeInterval: TimeInterval { TimeInterval(rawValue) }

    static var `default`: MaxRecordingDuration { .twentyMinutes }
}
