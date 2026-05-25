import Testing
@testable import Verborra

// MARK: - SensitiveMaskerTests (T018)

struct SensitiveMaskerTests {

    @Test func maskAPIKey_normalKey_showsLastFourChars() {
        let result = SensitiveMasker.maskAPIKey("sk-proj-abcdefghijklmnop1234")
        #expect(result == "sk-...1234")
    }

    @Test func maskAPIKey_shortKey_returnsStars() {
        #expect(SensitiveMasker.maskAPIKey("sk-123") == "***")
        #expect(SensitiveMasker.maskAPIKey("abc") == "***")
        #expect(SensitiveMasker.maskAPIKey("") == "***")
    }

    @Test func maskAPIKey_exactlyEightChars_works() {
        let result = SensitiveMasker.maskAPIKey("12345678")
        #expect(result == "sk-...5678")
    }

    @Test func maskTranscription_returnsLengthOnly() {
        let result = SensitiveMasker.maskTranscription("Hello, world!")
        #expect(result == "[transcription:13chars]")
    }

    @Test func maskTranscription_emptyString() {
        let result = SensitiveMasker.maskTranscription("")
        #expect(result == "[transcription:0chars]")
    }

    @Test func describeAudioBuffer_returnsMetadataOnly() {
        let result = SensitiveMasker.describeAudioBuffer(sampleCount: 16000, format: "f32")
        #expect(result == "[audio:16000samples,f32]")
    }

    @Test func maskHeaders_masksAuthorization() {
        let headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer sk-proj-abcdefghijklmnop1234"
        ]
        let masked = SensitiveMasker.maskHeaders(headers)
        #expect(masked["Content-Type"] == "application/json")
        #expect(masked["Authorization"]?.contains("sk-...") == true)
        #expect(masked["Authorization"]?.contains("abcdefg") != true)
    }
}
