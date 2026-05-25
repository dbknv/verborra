import Testing
@testable import Verborra

@Suite("LLMModel Tests")
struct LLMModelTests {

    @Test("GPT 5 Mini has correct raw value")
    func gpt5MiniRawValue() {
        #expect(LLMModel.gpt5Mini.rawValue == "gpt-5-mini")
    }

    @Test("GPT 5.1 has correct raw value")
    func gpt51RawValue() {
        #expect(LLMModel.gpt51.rawValue == "gpt-5.1")
    }

    @Test("GPT 5.2 has correct raw value")
    func gpt52RawValue() {
        #expect(LLMModel.gpt52.rawValue == "gpt-5.2")
    }

    @Test("GPT 5.3 has correct raw value")
    func gpt53RawValue() {
        #expect(LLMModel.gpt53.rawValue == "gpt-5.3")
    }

    @Test("New models have display names")
    func displayNames() {
        #expect(LLMModel.gpt5Mini.displayName == "GPT-5 Mini")
        #expect(LLMModel.gpt51.displayName == "GPT-5.1")
        #expect(LLMModel.gpt52.displayName == "GPT-5.2")
        #expect(LLMModel.gpt53.displayName == "GPT-5.3")
    }

    @Test("New models have descriptions with pricing")
    func infoDescriptions() {
        #expect(LLMModel.gpt5Mini.infoDescription.contains("$0.25"))
        #expect(LLMModel.gpt51.infoDescription.contains("$1.25"))
        #expect(LLMModel.gpt52.infoDescription.contains("$1.75"))
        #expect(LLMModel.gpt53.infoDescription.contains("$2.50"))
    }

    @Test("CaseIterable includes all 8 models")
    func allCases() {
        #expect(LLMModel.allCases.count == 8)
    }

    @Test("Default model is gpt41Nano")
    func defaultModel() {
        #expect(LLMModel.default == .gpt41Nano)
    }

    @Test("All models can be decoded from raw value")
    func decodable() {
        for model in LLMModel.allCases {
            #expect(LLMModel(rawValue: model.rawValue) == model)
        }
    }
}
