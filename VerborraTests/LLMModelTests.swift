import Testing
@testable import Verborra

// MARK: - LLMModelTests (spec 015, T018)

@Suite("LLMModel Tests")
struct LLMModelTests {

    private static let expected: [(LLMModel, String, String)] = [
        (.gpt52, "gpt-5.2", "GPT-5.2"),
        (.gpt54Mini, "gpt-5.4-mini", "GPT-5.4 Mini"),
        (.gpt54, "gpt-5.4", "GPT-5.4"),
        (.gpt55, "gpt-5.5", "GPT-5.5"),
        (.gpt56Terra, "gpt-5.6-terra", "GPT-5.6 Terra"),
        (.gpt56Sol, "gpt-5.6-sol", "GPT-5.6 Sol"),
        (.gpt6Luna, "gpt-6-luna", "GPT-6 Luna"),
        (.gpt6Sol, "gpt-6-sol", "GPT-6 Sol"),
        (.gpt61Sol, "gpt-6.1-sol", "GPT-6.1 Sol"),
        (.gpt6Astra, "gpt-6-astra", "GPT-6 Astra")
    ]

    @Test("allCases lists the 10 models in display order")
    func allCasesOrder() {
        #expect(LLMModel.allCases == Self.expected.map(\.0))
    }

    @Test("Raw values and display names")
    func rawValuesAndDisplayNames() {
        for (model, raw, name) in Self.expected {
            #expect(model.rawValue == raw)
            #expect(model.displayName == name)
        }
    }

    @Test("Default model is GPT-6 Luna")
    func defaultModel() {
        #expect(LLMModel.default == .gpt6Luna)
        #expect(LLMModel.legacyDefaultRawValue == "gpt-5.1")
    }

    @Test("Every model round-trips through its raw value (FR-039)")
    func roundTrip() {
        for model in LLMModel.allCases {
            #expect(LLMModel(rawValue: model.rawValue) == model)
        }
    }

    @Test("Removed model IDs no longer decode",
          arguments: ["gpt-4o-mini", "gpt-4.1-mini", "gpt-5-nano", "gpt-5-mini",
                      "gpt-5.1", "gpt-5.4-nano", "gpt-5.4-pro", "gpt-5.5-pro"])
    func removedIDs(rawValue: String) {
        #expect(LLMModel(rawValue: rawValue) == nil)
    }

    @Test("supportsTemperature per model")
    func temperatureTable() {
        let expected: [LLMModel: Bool] = [
            .gpt52: true, .gpt54Mini: false, .gpt54: true, .gpt55: true,
            .gpt56Terra: false, .gpt56Sol: false, .gpt6Luna: false,
            .gpt6Sol: false, .gpt61Sol: false, .gpt6Astra: false
        ]
        for model in LLMModel.allCases {
            #expect(model.supportsTemperature == expected[model], "\(model)")
        }
    }

    @Test("reasoningEffort per model")
    func reasoningEffortTable() {
        let expected: [LLMModel: ReasoningEffort?] = [
            .gpt52: nil, .gpt54Mini: nil, .gpt54: nil, .gpt55: nil,
            .gpt56Terra: ReasoningEffort.none, .gpt56Sol: ReasoningEffort.none,
            .gpt6Luna: ReasoningEffort.none, .gpt6Sol: ReasoningEffort.none,
            .gpt61Sol: .low, .gpt6Astra: .low
        ]
        for model in LLMModel.allCases {
            #expect(model.reasoningEffort == expected[model] ?? nil, "\(model)")
        }
    }

    @Test("Every model description shows a price in English and Russian (FR-034)")
    @MainActor
    func descriptionsShowPrices() {
        let manager = LocalizationManager.shared
        let original = manager.currentLanguage
        defer { manager.currentLanguage = original }
        for language in [SupportedLanguage.ru, .en] {
            manager.currentLanguage = language
            for model in LLMModel.allCases {
                #expect(model.infoDescription.contains("$"), "\(model) \(language)")
                #expect(!model.infoDescription.hasPrefix("model."), "\(model) \(language)")
            }
        }
    }
}
