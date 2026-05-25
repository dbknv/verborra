import Foundation
import Testing
@testable import Verborra

// MARK: - LogEntryTests (T021)

struct LogEntryTests {

    @Test func logEntry_encodesToJSON_allFieldsPresent() throws {
        let entry = LogEntry(
            level: .info,
            category: .audio,
            sessionId: "test-session-id",
            message: "Device selected",
            metadata: ["deviceName": "AirPods"]
        )
        let data = try JSONEncoder().encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["level"] as? String == "INFO")
        #expect(json["category"] as? String == "audio")
        #expect(json["sessionId"] as? String == "test-session-id")
        #expect(json["message"] as? String == "Device selected")
        #expect((json["metadata"] as? [String: String])?["deviceName"] == "AirPods")
        #expect(json["timestamp"] != nil)
    }

    @Test func logEntry_timestampIsISO8601WithMilliseconds() throws {
        let entry = LogEntry(
            level: .debug,
            category: .api,
            sessionId: "s1",
            message: "test"
        )
        // ISO 8601 with fractional seconds: e.g., 2026-03-19T14:30:05.123Z
        let timestamp = entry.timestamp
        #expect(timestamp.contains("T"))
        #expect(timestamp.contains(".")) // fractional seconds
    }

    @Test func logEntry_withErrorContext_encodesCorrectly() throws {
        let breadcrumb = Breadcrumb(label: "step1", category: .engine)
        let state = AppState(
            activeDevice: "AirPods",
            recordingStatus: "recording",
            recordingDuration: 5.0,
            currentOperation: "recording"
        )
        let errorContext = ErrorContext(
            description: "Engine failed",
            method: "startEngine",
            parameters: ["deviceId": "123"],
            errorCode: "AVError.cannotStart",
            state: state,
            breadcrumbs: [breadcrumb]
        )
        let entry = LogEntry(
            level: .error,
            category: .engine,
            sessionId: "s1",
            message: "Engine failed",
            error: errorContext
        )
        let data = try JSONEncoder().encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["level"] as? String == "ERROR")
        let errorObj = json["error"] as? [String: Any]
        #expect(errorObj?["description"] as? String == "Engine failed")
        #expect(errorObj?["method"] as? String == "startEngine")
        #expect(errorObj?["errorCode"] as? String == "AVError.cannotStart")
        let stateObj = errorObj?["state"] as? [String: Any]
        #expect(stateObj?["activeDevice"] as? String == "AirPods")
        let breadcrumbs = errorObj?["breadcrumbs"] as? [[String: Any]]
        #expect(breadcrumbs?.count == 1)
        #expect(breadcrumbs?[0]["label"] as? String == "step1")
    }

    @Test func logEntry_withoutError_errorFieldIsNil() throws {
        let entry = LogEntry(
            level: .info,
            category: .lifecycle,
            sessionId: "s1",
            message: "App launched"
        )
        let data = try JSONEncoder().encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["error"] == nil)
    }

    @Test func logEntry_decodesFromJSON() throws {
        let jsonString = """
        {"timestamp":"2026-03-19T14:30:05.123Z","level":"INFO","category":"audio","sessionId":"abc","message":"test","metadata":null,"error":null}
        """
        let data = jsonString.data(using: .utf8)!
        let entry = try JSONDecoder().decode(LogEntry.self, from: data)
        #expect(entry.level == "INFO")
        #expect(entry.category == "audio")
        #expect(entry.sessionId == "abc")
        #expect(entry.message == "test")
    }
}
