import Testing
@testable import LangSwitcherApp

struct TransliteratorTests {
    @Test func commonWords() {
        let transliterator = Transliterator()
        #expect(transliterator.candidates(for: "privet").contains("привет"))
        #expect(transliterator.candidates(for: "spasibo").contains("спасибо"))
        #expect(transliterator.candidates(for: "Poka").contains("Пока"))
    }

    @Test func rejectsNonASCII() {
        #expect(Transliterator().candidates(for: "приvet").isEmpty)
    }
}
