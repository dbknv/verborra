import Foundation

// MARK: - TranscriptionResult

struct TranscriptionResult {
    var rawText: String
    let timestamp: Date
    let audioDuration: TimeInterval
}
