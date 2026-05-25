@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import Verborra

@MainActor
struct AudioFileWriterTests {
    private func makeTempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFormat(sampleRate: Double = 44100, channels: UInt32 = 1) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
    }

    @Test("startWriting creates file with correct name")
    func testStartWritingCreatesFile() throws {
        let writer = AudioFileWriter()
        let folder = makeTempFolder()
        let format = makeFormat()

        let url = try writer.startWriting(deviceName: "Test Mic", sampleRate: 44100, format: format, folder: folder)

        #expect(url.pathExtension == "wav")
        #expect(url.lastPathComponent.contains("Test Mic"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(writer.isWriting)

        writer.stopWriting()
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("write appends data to file")
    func testWriteAppendsData() throws {
        let writer = AudioFileWriter()
        let folder = makeTempFolder()
        let format = makeFormat()

        let url = try writer.startWriting(deviceName: "Mic", sampleRate: 44100, format: format, folder: folder)

        // Create a test buffer
        if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) {
            buffer.frameLength = 1024
            try writer.write(buffer: buffer)
        }

        writer.stopWriting()

        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(fileSize > 0)

        try? FileManager.default.removeItem(at: folder)
    }

    @Test("stopWriting closes file")
    func testStopWritingClosesFile() throws {
        let writer = AudioFileWriter()
        let folder = makeTempFolder()
        let format = makeFormat()

        _ = try writer.startWriting(deviceName: "Mic", sampleRate: 44100, format: format, folder: folder)
        #expect(writer.isWriting)

        writer.stopWriting()
        #expect(!writer.isWriting)

        try? FileManager.default.removeItem(at: folder)
    }

    @Test("sanitizeFileName replaces special characters")
    func testSanitizeFileName() {
        #expect(AudioFileWriter.sanitizeFileName("A/B:C\\D") == "A_B_C_D")
        #expect(AudioFileWriter.sanitizeFileName("Normal Name") == "Normal Name")
    }
}
