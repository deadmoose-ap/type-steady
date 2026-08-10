import Foundation
import Carbon

@MainActor
enum SelfTestRunner {
    static func run() -> Int32 {
        var failures: [String] = []

        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failures.append(name)
            }
        }

        let transliterator = Transliterator()
        check(transliterator.candidates(for: "privet").contains("привет"), "transliteration.basic")
        check(transliterator.candidates(for: "spasibo").contains("спасибо"), "transliteration.digraphs")
        check(transliterator.candidates(for: "приvet").isEmpty, "transliteration.mixed.backlog")
        check(LocalLexicon().contains("привет", language: .russian), "lexicon.bundle-resource")
        check(HotkeyChoice.optionSpace.carbonModifiers == UInt32(optionKey), "hotkey.option-space")
        check(
            HotkeyChoice.optionSpace.selectionCarbonModifiers == UInt32(optionKey | cmdKey),
            "hotkey.option-space-selection"
        )
        check(HotkeyChoice(rawValue: 0) == .controlOptionSpace, "hotkey.raw-value-0")
        check(HotkeyChoice(rawValue: 1) == .controlShiftSpace, "hotkey.raw-value-1")
        check(HotkeyChoice(rawValue: 2) == .commandOptionSpace, "hotkey.raw-value-2")

        let emojiSource = String(repeating: "а", count: 19) + "🙂" + "б"
        let chunks = EventSynthesizer.chunkUTF16(emojiSource, maximumCodeUnits: 20)
        check(chunks.map(\.count) == [19, 3], "unicode.surrogate-boundary")

        var state = TypingStateMachine()
        let context = AppContext(processIdentifier: 1, bundleIdentifier: "self.test")
        let key = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        _ = state.consume(key: key, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1)
        let completed = state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ",
            alternateCharacter: " ",
            context: context,
            timestamp: 2
        )
        check(completed?.deletionCount == 2, "state.word-boundary")
        state.backspace(timestamp: 3)
        check(state.activeKeys == [key], "state.backspace-reopen")

        var punctuationState = TypingStateMachine()
        _ = punctuationState.consume(key: key, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1)
        _ = punctuationState.consume(
            key: PhysicalKey(keyCode: 47, shift: false, capsLock: false),
            currentCharacter: ".",
            alternateCharacter: "ю",
            context: context,
            timestamp: 2
        )
        let punctuationToken = punctuationState.consume(
            key: PhysicalKey(keyCode: 18, shift: true, capsLock: false),
            currentCharacter: "!",
            alternateCharacter: "!",
            context: context,
            timestamp: 3
        )
        check(punctuationToken?.variants.first?.boundary == ".!", "state.punctuation-chain")
        check(punctuationToken?.deletionCount == 3, "state.punctuation-deletion-count")

        let selectionKeys = (0..<6).map { PhysicalKey(keyCode: UInt16($0), shift: false, capsLock: false) }
        let englishLayout = KeyboardLayoutSnapshot.testLayout(
            id: "en",
            name: "English",
            language: .english,
            characters: Dictionary(uniqueKeysWithValues: zip(selectionKeys, ["g", "h", "b", "d", "t", "n"]))
        )
        let russianLayout = KeyboardLayoutSnapshot.testLayout(
            id: "ru",
            name: "Russian",
            language: .russian,
            characters: Dictionary(uniqueKeysWithValues: zip(selectionKeys, ["п", "р", "и", "в", "е", "т"]))
        )
        let selectedResult = SelectedTextConverter().convert("ghbdtn", english: englishLayout, russian: russianLayout)
        check(selectedResult?.text == "привет", "selection.dynamic-layout-map")

        let lexicon = LocalLexicon(common: [.english: ["hello"], .russian: ["привет"]])
        let detector = DetectionEngine(lexicon: lexicon, spellChecker: NullSpellChecker())
        let defaultsName = "LangSwitcher.SelfTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        let proposal = detector.proposal(
            current: "ghbdtn",
            alternate: "привет",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: settings
        )
        check(proposal?.kind == .layout, "detection.layout")
        let kept = detector.proposal(
            current: "hello",
            alternate: "руддщ",
            sourceLanguage: .english,
            targetLanguage: .russian,
            context: context,
            settings: settings
        )
        check(kept == nil, "detection.keep-known")

        let policy = AppPolicy()
        check(policy.isStructurallyProtected("some_value", inCodeEditor: false), "policy.snake-case")
        check(!policy.isHardDenied(bundleIdentifier: "com.apple.dt.Xcode"), "policy.ide-enabled")

        if failures.isEmpty {
            print("SELF-TEST PASSED")
        } else {
            print("SELF-TEST FAILED count=\(failures.count)")
        }
        return Int32(failures.count)
    }
}
