import Foundation

// MARK: - InputRecordingState

enum InputRecordingState: Equatable {
    case idle
    case recording(duration: TimeInterval, remaining: TimeInterval)
    case processing
}
