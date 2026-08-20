import Foundation
import Testing
@testable import TypeSteadyApp

@MainActor
struct DetectionEngineTests {
    private let context = AppContext(processIdentifier: 1, bundleIdentifier: "test.editor")

    private func makeSettings() -> AppSettings {
        let suite = "TypeSteadyTests.\(UUID().uuidString)"
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
            context: context,
            settings: makeSettings()
        )
        #expect(proposal?.replacement == "привет")
        #expect(proposal?.kind == .layout)
    }

    // D3: воспроизводит документированный кейс z → я на РЕАЛЬНОМ упакованном лексиконе
    // (Sources/TypeSteadyApp/Resources/Dictionaries/ru_common.txt содержит "я") и с
    // NullSpellChecker — то есть без какой-либо помощи системного словаря, только
    // локальный лексикон + скоринг. plausibility() штрафует value.count < 2 на -1, а
    // requiredMargin для однобуквенных слов увеличен на 2.0 (count <= 2) — проверка того,
    // что запас всё ещё достаточен. По итогам прогона (см. отчёт) тест ПРОХОДИТ на текущих
    // весах — правки не потребовалось, тест остаётся регрессионным.
    @Test func documentedSingleLetterZToYaCaseHoldsOnRealLexiconWithoutSpellChecker() {
        let engine = DetectionEngine(lexicon: LocalLexicon(), spellChecker: NullSpellChecker())
        let proposal = engine.proposal(
            current: "z",
            alternate: "я",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: makeSettings()
        )
        #expect(proposal?.replacement == "я")
        #expect(proposal?.kind == .layout)
    }

    @Test func detectsKnownSingleLetterWord() {
        let lexicon = LocalLexicon(common: [
            .english: [],
            .russian: ["я"]
        ])
        let engine = DetectionEngine(lexicon: lexicon, spellChecker: NullSpellChecker())
        let proposal = engine.proposal(
            current: "z",
            alternate: "я",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: makeSettings()
        )

        #expect(proposal?.replacement == "я")
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
            context: context,
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
            context: context,
            settings: makeSettings()
        )
        #expect(proposal?.replacement == "привет")
        #expect(proposal?.kind == .transliteration)
    }

    @Test func neverCorrectsWordsContainedInReservedPhrase() {
        let settings = makeSettings()
        settings.neverConvert = "ghbdtn special"
        let lexicon = LocalLexicon(common: [
            .english: [],
            .russian: ["привет"]
        ])
        let engine = DetectionEngine(lexicon: lexicon, spellChecker: NullSpellChecker())

        let proposal = engine.proposal(
            current: "ghbdtn",
            alternate: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: settings
        )

        #expect(proposal == nil)
    }

    @Test func neverRuleHandlesCaseUnicodeAndWinsOverAlwaysRule() {
        let settings = makeSettings()
        settings.neverConvert = "CAFÉ"
        settings.alwaysConvert = "cafe\u{301}"
        let engine = DetectionEngine(
            lexicon: LocalLexicon(common: [.english: [], .russian: ["кафе"]]),
            spellChecker: NullSpellChecker()
        )

        let proposal = engine.proposal(
            current: "cafe\u{301}",
            alternate: "кафе",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: settings
        )

        #expect(proposal == nil)
    }

    @Test func alwaysRuleBypassesDictionaryDecision() {
        let settings = makeSettings()
        settings.alwaysConvert = "zzzz"
        let engine = DetectionEngine(
            lexicon: LocalLexicon(common: [.english: [], .russian: []]),
            spellChecker: NullSpellChecker()
        )

        let proposal = engine.proposal(
            current: "zzzz",
            alternate: "яяяя",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: settings
        )

        #expect(proposal?.kind == .layout)
        #expect(proposal?.confidence == 1)
    }

    // D1: alwaysConvert раньше кэшировался простым lineSet (сравнение целой строки), поэтому
    // многословный термин никогда не срабатывал — решение принимается на границе каждого
    // отдельного слова, а второе слово фразы никогда не совпадёт с целой строкой правила.
    // Симметрично neverCorrectsWordsContainedInReservedPhrase выше: каждый компонент
    // многословной фразы в «Всегда исправлять» обязан сработать по отдельности.
    @Test func alwaysRuleAppliesToEachWordOfMultiWordPhrase() {
        let settings = makeSettings()
        settings.alwaysConvert = "ghbdtn vczz"
        let engine = DetectionEngine(
            lexicon: LocalLexicon(common: [.english: [], .russian: []]),
            spellChecker: NullSpellChecker()
        )

        let first = engine.proposal(
            current: "ghbdtn",
            alternate: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: settings
        )
        let second = engine.proposal(
            current: "vczz",
            alternate: "домен",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: settings
        )

        #expect(first?.kind == .layout)
        #expect(first?.confidence == 1)
        #expect(second?.kind == .layout)
        #expect(second?.confidence == 1)
    }

    // D1/D2: «Никогда» приоритетнее «Всегда» даже когда оба списка многословные и делят
    // общее слово — проверка неверного порядка нормализации (DetectionEngine.normalize vs
    // UserTermRules.normalize) не должна расколоть это сравнение на два разных набора.
    @Test func neverRuleWinsOverAlwaysRuleForMultiWordPhrases() {
        let settings = makeSettings()
        settings.neverConvert = "reserved term"
        settings.alwaysConvert = "reserved term"
        let engine = DetectionEngine(
            lexicon: LocalLexicon(common: [.english: [], .russian: ["термин"]]),
            spellChecker: NullSpellChecker()
        )

        let proposal = engine.proposal(
            current: "term",
            alternate: "термин",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: settings
        )

        #expect(proposal == nil)
    }

    @Test func respectsExcludedApplicationsAndPasswordManagers() {
        let settings = makeSettings()
        settings.excludedBundleIDs = "COM.EXAMPLE.BLOCKED"
        let engine = DetectionEngine(
            lexicon: LocalLexicon(common: [.english: [], .russian: ["привет"]]),
            spellChecker: NullSpellChecker()
        )

        let excluded = engine.proposal(
            current: "ghbdtn",
            alternate: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: AppContext(processIdentifier: 1, bundleIdentifier: "com.example.blocked"),
            settings: settings
        )
        let passwordManager = engine.proposal(
            current: "ghbdtn",
            alternate: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: AppContext(processIdentifier: 1, bundleIdentifier: "com.1password.desktop"),
            settings: settings
        )

        #expect(excluded == nil)
        #expect(passwordManager == nil)
    }

    @Test func neverCorrectsInsideTypeSteadySettings() {
        let settings = makeSettings()
        settings.alwaysConvert = "ghbdtn"
        let engine = DetectionEngine(
            lexicon: LocalLexicon(common: [.english: [], .russian: ["привет"]]),
            spellChecker: NullSpellChecker()
        )

        let proposal = engine.proposal(
            current: "ghbdtn",
            alternate: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: AppContext(
                processIdentifier: 1,
                bundleIdentifier: AppPolicy.typeSteadyBundleIdentifier
            ),
            settings: settings
        )

        #expect(proposal == nil)
    }

    @Test func respectsTransliterationToggle() {
        let settings = makeSettings()
        settings.transliteration = false
        let engine = DetectionEngine(
            lexicon: LocalLexicon(common: [.english: [], .russian: ["привет"]]),
            spellChecker: NullSpellChecker()
        )

        let proposal = engine.proposal(
            current: "privet",
            alternate: "зкшмуе",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: settings
        )

        #expect(proposal == nil)
    }

    @Test func rejectsKnownCurrentIdenticalAndStructuredTokens() {
        let settings = makeSettings()
        settings.alwaysConvert = "same\nsome_value"
        let engine = DetectionEngine(
            lexicon: LocalLexicon(common: [.english: ["a"], .russian: []]),
            spellChecker: NullSpellChecker()
        )

        #expect(engine.proposal(
            current: "a", alternate: "ф", sourceLanguage: .english, targetLanguage: .russian,
            context: context, settings: settings
        ) == nil)
        #expect(engine.proposal(
            current: "same", alternate: "same", sourceLanguage: .english, targetLanguage: .russian,
            context: context, settings: settings
        ) == nil)
        #expect(engine.proposal(
            current: "some_value", alternate: "ыщьу_мфдгу", sourceLanguage: .english, targetLanguage: .russian,
            context: context, settings: settings
        ) == nil)
    }

    @Test func forcedProposalPreservesRequestedConversion() {
        let engine = DetectionEngine(
            lexicon: LocalLexicon(common: [:]),
            spellChecker: NullSpellChecker()
        )
        let proposal = engine.forcedProposal(
            current: "ghbdtn",
            alternate: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian
        )

        #expect(proposal.original == "ghbdtn")
        #expect(proposal.replacement == "привет")
        #expect(proposal.kind == .forced)
        #expect(proposal.confidence == 1)
    }
}
