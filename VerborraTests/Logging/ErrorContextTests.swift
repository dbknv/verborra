import Foundation
import Testing
@testable import Verborra

// MARK: - ErrorContextTests (T038)

struct ErrorContextTests {

    @Test func errorContext_withBreadcrumbs_containsAll() {
        let breadcrumbs = [
            Breadcrumb(label: "step1", category: .audio),
            Breadcrumb(label: "step2", category: .engine),
            Breadcrumb(label: "step3", category: .api)
        ]
        let state = AppState(
            activeDevice: "AirPods",
            recordingStatus: "recording",
            recordingDuration: 5.0,
            currentOperation: "recording"
        )
        let ctx = ErrorContext(
            description: "Engine failed",
            method: "startEngine",
            parameters: ["deviceId": "123"],
            errorCode: "AVError",
            state: state,
            breadcrumbs: breadcrumbs
        )

        #expect(ctx.breadcrumbs.count == 3)
        #expect(ctx.breadcrumbs[0].label == "step1")
        #expect(ctx.state?.activeDevice == "AirPods")
        #expect(ctx.method == "startEngine")
    }

    @Test func errorContext_withoutFlow_emptyBreadcrumbs() {
        let ctx = ErrorContext(
            description: "Some error",
            method: "someMethod",
            parameters: nil,
            errorCode: nil,
            state: nil,
            breadcrumbs: []
        )
        #expect(ctx.breadcrumbs.isEmpty)
        #expect(ctx.state == nil)
    }

    @Test func errorContext_encodesToJSON() throws {
        let ctx = ErrorContext(
            description: "Test",
            method: "test",
            parameters: ["a": "b"],
            errorCode: "E001",
            state: AppState(activeDevice: nil, recordingStatus: "idle", recordingDuration: nil, currentOperation: nil),
            breadcrumbs: [Breadcrumb(label: "bc1", category: .lifecycle)]
        )
        let data = try JSONEncoder().encode(ctx)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["description"] as? String == "Test")
        #expect(json["method"] as? String == "test")
        #expect(json["errorCode"] as? String == "E001")
        let bcs = json["breadcrumbs"] as? [[String: Any]]
        #expect(bcs?.count == 1)
    }
}
