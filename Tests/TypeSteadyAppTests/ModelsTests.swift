import Testing
@testable import TypeSteadyApp

struct ModelsTests {
    @Test func classifiesInputCharacters() {
        #expect(Character("A").isLetterOrNumber)
        #expect(Character("я").isLetterOrNumber)
        #expect(Character("7").isLetterOrNumber)
        #expect(!Character("!").isLetterOrNumber)
        #expect(Character(" ").isWhitespace)
        #expect(Character("\n").isWhitespace)
        #expect(Character("!").isPunctuationOrSymbol)
        #expect(Character("€").isPunctuationOrSymbol)
    }

    @Test func languageNamesRemainUserFacing() {
        #expect(LanguageCode.english.displayName == "English")
        #expect(LanguageCode.russian.displayName == "Русский")
    }
}
