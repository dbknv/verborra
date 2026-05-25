@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioFileWriting

protocol AudioFileWriting {
    /// Start writing audio to a new WAV file.
    /// - Parameters:
    ///   - deviceName: Device name for the file name.
    ///   - sampleRate: Audio sample rate.
    ///   - format: Audio format (channels, bit depth).
    ///   - folder: Destination folder URL.
    /// - Returns: URL of the created file.
    func startWriting(
        deviceName: String,
        sampleRate: Float64,
        format: AVAudioFormat,
        folder: URL
    ) throws -> URL

    /// Write an audio buffer to the current file.
    func write(buffer: AVAudioPCMBuffer) throws

    /// Stop writing and close the current file.
    func stopWriting()

    /// Whether a file is currently being written.
    var isWriting: Bool { get }
}
