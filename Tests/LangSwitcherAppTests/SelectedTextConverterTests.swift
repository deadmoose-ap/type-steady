import Testing
@testable import LangSwitcherApp

struct SelectedTextConverterTests {
    @Test func convertsByPhysicalKeys() {
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

        let result = SelectedTextConverter().convert("ghbdtn", english: english, russian: russian)
        #expect(result?.text == "привет")
        #expect(result?.sourceLanguage == .english)
        #expect(result?.targetLanguage == .russian)
    }
}
