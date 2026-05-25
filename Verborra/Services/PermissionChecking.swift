import Foundation

// MARK: - PermissionType (T001)

enum PermissionType: String, CaseIterable {
    case microphone
    case accessibility

    var isRequired: Bool {
        switch self {
        case .microphone: return true
        case .accessibility: return false
        }
    }

    var systemSettingsURL: String {
        switch self {
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}

// MARK: - PermissionStatus (T001)

enum PermissionStatus: String {
    case notDetermined
    case granted
    case denied
    case restricted
}

// MARK: - PermissionChecking (T002)

protocol PermissionChecking: AnyObject {
    var microphoneStatus: PermissionStatus { get }
    var accessibilityStatus: PermissionStatus { get }

    func requestMicrophoneAccess()
    func requestAccessibilityAccess()
    func startMonitoring()
    func stopMonitoring()
}
