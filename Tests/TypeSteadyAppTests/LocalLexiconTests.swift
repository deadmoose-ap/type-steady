import Testing
@testable import TypeSteadyApp

struct LocalLexiconTests {
    @Test func loadsPackagedDictionaryResources() {
        let lexicon = LocalLexicon()
        #expect(lexicon.contains("привет", language: .russian))
        #expect(lexicon.contains("hello", language: .english))
    }

    @Test func normalizesCaseAndCanonicalUnicode() {
        let lexicon = LocalLexicon(
            common: [.english: ["café"]],
            extended: [.russian: ["термин"]]
        )
        #expect(lexicon.contains("CAFE\u{301}", language: .english))
        #expect(lexicon.contains("ТЕРМИН", language: .russian))
        #expect(lexicon.score("café", language: .english) == 6)
        #expect(lexicon.score("термин", language: .russian) == 4.5)
        #expect(lexicon.score("unknown", language: .english) == 0)
    }
}
