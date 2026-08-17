import Testing
@testable import TypeSteadyApp

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

    @Test func handlesDigraphsAndCase() {
        let transliterator = Transliterator()
        #expect(transliterator.candidates(for: "shchuka").contains("щука"))
        #expect(transliterator.candidates(for: "ZHUK").contains("ЖУК"))
        #expect(transliterator.candidates(for: "Poka").contains("Пока"))
    }

    @Test func obeysCandidateLimitAndRejectsUnmappedASCII() {
        let transliterator = Transliterator()
        #expect(transliterator.candidates(for: "cycycy", limit: 3).count <= 3)
        #expect(transliterator.candidates(for: "hello!").isEmpty)
    }
}
