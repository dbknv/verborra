import Testing
@testable import Verborra

@Suite("OnboardingStep Tests")
struct OnboardingStateTests {

    @Test("Steps have correct raw values")
    func stepRawValues() {
        #expect(OnboardingStep.welcome.rawValue == 0)
        #expect(OnboardingStep.permissions.rawValue == 1)
        #expect(OnboardingStep.microphoneTest.rawValue == 2)
        #expect(OnboardingStep.completion.rawValue == 3)
    }

    @Test("Step navigation forward")
    func stepNext() {
        #expect(OnboardingStep.welcome.next == .permissions)
        #expect(OnboardingStep.permissions.next == .microphoneTest)
        #expect(OnboardingStep.microphoneTest.next == .completion)
        #expect(OnboardingStep.completion.next == nil)
    }

    @Test("Step navigation backward")
    func stepPrevious() {
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.permissions.previous == .welcome)
        #expect(OnboardingStep.microphoneTest.previous == .permissions)
        #expect(OnboardingStep.completion.previous == .microphoneTest)
    }

    @Test("Only completion step is last")
    func isLast() {
        #expect(!OnboardingStep.welcome.isLast)
        #expect(!OnboardingStep.permissions.isLast)
        #expect(!OnboardingStep.microphoneTest.isLast)
        #expect(OnboardingStep.completion.isLast)
    }

    @Test("CaseIterable includes all 4 steps")
    func allCases() {
        #expect(OnboardingStep.allCases.count == 4)
    }
}
