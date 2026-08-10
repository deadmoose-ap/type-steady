import Testing
@testable import LangSwitcherApp

@MainActor
struct DetectionEngineTests {
    private func makeSettings() -> AppSettings {
        let suite = "LangSwitcherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    @Test func detectsWrongLayout() {
        let lexicon = LocalLexicon(common: [
            .english: ["hello"],
            .russian: ["привет"]
        ])
        let engine = DetectionEngine(lexicon: lexicon, spellChecker: NullSpellChecker())
        let proposal = engine.proposal(
            current: "ghbdtn",
            alternate: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: AppContext(processIdentifier: 1, bundleIdentifier: "test.editor"),
            settings: makeSettings()
        )
        #expect(proposal?.replacement == "привет")
        #expect(proposal?.kind == .layout)
    }

    @Test func keepsKnownCurrentWord() {
        let lexicon = LocalLexicon(common: [
            .english: ["hello"],
            .russian: ["руддщ"]
        ])
        let engine = DetectionEngine(lexicon: lexicon, spellChecker: NullSpellChecker())
        let proposal = engine.proposal(
            current: "hello",
            alternate: "руддщ",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: AppContext(processIdentifier: 1, bundleIdentifier: "test.editor"),
            settings: makeSettings()
        )
        #expect(proposal == nil)
    }

    @Test func detectsPhoneticTransliteration() {
        let lexicon = LocalLexicon(common: [
            .english: [],
            .russian: ["привет"]
        ])
        let engine = DetectionEngine(lexicon: lexicon, spellChecker: NullSpellChecker())
        let proposal = engine.proposal(
            current: "privet",
            alternate: "зкшмуе",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: AppContext(processIdentifier: 1, bundleIdentifier: "test.editor"),
            settings: makeSettings()
        )
        #expect(proposal?.replacement == "привет")
        #expect(proposal?.kind == .transliteration)
    }
}
