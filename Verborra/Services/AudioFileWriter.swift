@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioFileWriter

/// Thread-safe WAV file writer. `startWriting`/`stopWriting` called from main thread,
/// `write(buffer:)` called from real-time audio thread.
final class AudioFileWriter: AudioFileWriting, @unchecked Sendable {
    private var audioFile: AVAudioFile?
    private var currentFileURL: URL?
    private let lock = NSLock()
    private let log = DiagnosticLogger.logger(for: .audio)

    var isWriting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return audioFile != nil
    }

    func startWriting(
        deviceName: String,
        sampleRate: Float64,
        format: AVAudioFormat,
        folder: URL
    ) throws -> URL {
        lock.lock()
        if audioFile != nil {
            audioFile = nil
            currentFileURL = nil
        }
        lock.unlock()

        let sanitizedName = Self.sanitizeFileName(deviceName)
        let timestamp = Self.currentTimestamp()
        let fileName = "\(timestamp)_\(sanitizedName).wav"
        let fileURL = folder.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let outputFormat = AVAudioFormat(settings: settings) else {
            throw AudioFileWriterError.invalidFormat
        }

        let file = try AVAudioFile(forWriting: fileURL, settings: outputFormat.settings)

        lock.lock()
        audioFile = file
        currentFileURL = fileURL
        lock.unlock()

        log.info("AudioFileWriter started", metadata: [
            "file": fileName,
            "sampleRate": "\(sampleRate)",
            "channels": "\(format.channelCount)",
        ])

        return fileURL
    }

    /// Called from real-time audio thread — must be lock-free safe.
    /// Uses NSLock (not ideal for RT, but file I/O already blocks).
    func write(buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        guard let file = audioFile else {
            lock.unlock()
            return
        }
        do {
            try file.write(from: buffer)
            lock.unlock()
        } catch let error as NSError where error.code == NSFileWriteOutOfSpaceError {
            audioFile = nil
            currentFileURL = nil
            lock.unlock()
            log.error("Disk full — stopping file write", errorCode: "diskFull")
        } catch {
            lock.unlock()
            log.error("AudioFileWriter write error: \(error.localizedDescription)",
                      errorCode: "fileWriteError")
        }
    }

    func stopWriting() {
        lock.lock()
        guard audioFile != nil else {
            lock.unlock()
            return
        }
        let url = currentFileURL
        audioFile = nil
        currentFileURL = nil
        lock.unlock()

        if let url {
            log.info("AudioFileWriter stopped", metadata: ["file": url.lastPathComponent])
        }
    }

    // MARK: - Helpers

    static func sanitizeFileName(_ name: String) -> String {
        var sanitized = name
        for char in ["/", ":", "\\"] {
            sanitized = sanitized.replacingOccurrences(of: char, with: "_")
        }
        return sanitized
    }

    private static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}

// MARK: - AudioFileWriterError

enum AudioFileWriterError: Error {
    case invalidFormat
}
