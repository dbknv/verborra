import Testing
@testable import Verborra

// MARK: - STTModelTests (spec 015, T019)

@Suite("STTModel Tests")
struct STTModelTests {

    @Test("Only GPT Transcribe is offered")
    func allCases() {
        #expect(STTModel.allCases == [.gptTranscribe])
        #expect(STTModel.gptTranscribe.rawValue == "gpt-transcribe")
        #expect(STTModel.gptTranscribe.displayName == "GPT Transcribe")
    }

    @Test("Default is GPT Transcribe")
    func defaultModel() {
        #expect(STTModel.default == .gptTranscribe)
        #expect(STTModel.legacyDefaultRawValue == "gpt-4o-mini-transcribe")
    }

    @Test("GPT Transcribe sends languages[]")
    func languageField() {
        #expect(STTModel.gptTranscribe.languageField == .languagesArray)
    }

    @Test("Removed model IDs no longer decode",
          arguments: ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"])
    func removedIDs(rawValue: String) {
        #expect(STTModel(rawValue: rawValue) == nil)
    }

    @Test("Every model description shows a price in English and Russian (FR-034)")
    @MainActor
    func descriptionsShowPrices() {
        let manager = LocalizationManager.shared
        let original = manager.currentLanguage
        defer { manager.currentLanguage = original }
        for language in [SupportedLanguage.ru, .en] {
            manager.currentLanguage = language
            for model in STTModel.allCases {
                #expect(model.infoDescription.contains("$"), "\(model) \(language)")
                #expect(!model.infoDescription.hasPrefix("model."), "\(model) \(language)")
            }
        }
    }
}
