import Testing
@testable import Verborra

// MARK: - FlowTrackerTests (T020)

struct FlowTrackerTests {

    @Test func beginFlow_createsUniqueFlowId() {
        let tracker = FlowTracker.shared
        let id1 = tracker.beginFlow()
        let id2 = tracker.beginFlow()
        #expect(id1 != id2)
        // Cleanup
        _ = tracker.endFlow(id1)
        _ = tracker.endFlow(id2)
    }

    @Test func addBreadcrumb_andEndFlow_returnsBreadcrumbs() {
        let tracker = FlowTracker.shared
        let flowId = tracker.beginFlow()
        let bc1 = Breadcrumb(label: "step1", category: .audio)
        let bc2 = Breadcrumb(label: "step2", category: .engine)
        tracker.addBreadcrumb(bc1, to: flowId)
        tracker.addBreadcrumb(bc2, to: flowId)
        let result = tracker.endFlow(flowId)
        #expect(result.count == 2)
        #expect(result[0].label == "step1")
        #expect(result[1].label == "step2")
    }

    @Test func endFlow_removesFlow() {
        let tracker = FlowTracker.shared
        let flowId = tracker.beginFlow()
        tracker.addBreadcrumb(Breadcrumb(label: "test", category: .audio), to: flowId)
        _ = tracker.endFlow(flowId)
        // Second drain returns empty
        let result = tracker.endFlow(flowId)
        #expect(result.isEmpty)
    }

    @Test func endFlow_unknownId_returnsEmpty() {
        let tracker = FlowTracker.shared
        let result = tracker.endFlow(UUID())
        #expect(result.isEmpty)
    }

    @Test func breadcrumbs_respectRingBufferCapacity() {
        let tracker = FlowTracker.shared
        let flowId = tracker.beginFlow()
        for i in 0..<25 {
            tracker.addBreadcrumb(Breadcrumb(label: "step_\(i)", category: .audio), to: flowId)
        }
        let result = tracker.endFlow(flowId)
        #expect(result.count == 20) // capacity = 20
        #expect(result[0].label == "step_5") // oldest surviving
        #expect(result[19].label == "step_24") // newest
    }
}
