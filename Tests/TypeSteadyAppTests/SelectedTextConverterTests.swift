import Testing
@testable import TypeSteadyApp

struct SelectedTextConverterTests {
    private func layouts() -> (KeyboardLayoutSnapshot, KeyboardLayoutSnapshot) {
        let keys = (0..<6).map { PhysicalKey(keyCode: UInt16($0), shift: false, capsLock: false) }
        let english = KeyboardLayoutSnapshot.testLayout(
            id: "en",
            name: "English",
            language: .english,
            characters: Dictionary(uniqueKeysWithValues: zip(keys, ["g", "h", "b", "d", "t", "n"]))
        )
        let russian = KeyboardLayoutSnapshot.testLayout(
            id: "ru",
            name: "Russian",
            language: .russian,
            characters: Dictionary(uniqueKeysWithValues: zip(keys, ["п", "р", "и", "в", "е", "т"]))
        )
        return (english, russian)
    }

    @Test func convertsByPhysicalKeys() {
        let (english, russian) = layouts()

        let result = SelectedTextConverter().convert("ghbdtn", english: english, russian: russian)
        #expect(result?.text == "привет")
        #expect(result?.sourceLanguage == .english)
        #expect(result?.targetLanguage == .russian)
    }

    @Test func convertsCyrillicBackToLatin() {
        let (english, russian) = layouts()
        let result = SelectedTextConverter().convert("привет", english: english, russian: russian)
        #expect(result?.text == "ghbdtn")
        #expect(result?.sourceLanguage == .russian)
        #expect(result?.targetLanguage == .english)
    }

    @Test func preservesUnsupportedCharacters() {
        let (english, russian) = layouts()
        let result = SelectedTextConverter().convert("gh!", english: english, russian: russian)
        #expect(result?.text == "пр!")
    }

    @Test func rejectsTextWithoutLettersOrConvertibleCharacters() {
        let (english, russian) = layouts()
        #expect(SelectedTextConverter().convert("123!?", english: english, russian: russian) == nil)
        #expect(SelectedTextConverter().convert("xyz", english: english, russian: russian) == nil)
    }
}
