import Foundation
import SwiftUI

// MARK: - OnboardingStep

enum OnboardingStep: Int, Codable, CaseIterable {
    case welcome = 0
    case permissions = 1
    case microphoneTest = 2
    case completion = 3

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

    var isLast: Bool {
        self == .completion
    }
}
