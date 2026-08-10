import CoreGraphics
import Testing
@testable import LangSwitcherApp

struct TypingStateMachineTests {
    private let context = AppContext(processIdentifier: 42, bundleIdentifier: "test.editor")

    @Test func completesWordOnSpace() {
        var state = TypingStateMachine()
        let first = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        let second = PhysicalKey(keyCode: 5, shift: false, capsLock: false)

        #expect(state.consume(
            key: first,
            currentCharacter: "h",
            alternateCharacter: "р",
            context: context,
            timestamp: 1
        ) == nil)
        #expect(state.consume(
            key: second,
            currentCharacter: "i",
            alternateCharacter: "ш",
            context: context,
            timestamp: 2
        ) == nil)
        let token = state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ",
            alternateCharacter: " ",
            context: context,
            timestamp: 3
        )

        #expect(token?.variants.first?.keys == [first, second])
        #expect(token?.variants.first?.boundary == " ")
        #expect(token?.deletionCount == 3)
    }

    @Test func ambiguousPunctuationProducesTwoVariants() {
        var state = TypingStateMachine()
        let letter = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        let punctuation = PhysicalKey(keyCode: 47, shift: false, capsLock: false)
        _ = state.consume(key: letter, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1)
        #expect(state.consume(
            key: punctuation,
            currentCharacter: ".",
            alternateCharacter: "ю",
            context: context,
            timestamp: 2
        ) == nil)

        let token = state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ",
            alternateCharacter: " ",
            context: context,
            timestamp: 3
        )
        #expect(token?.variants.count == 2)
        #expect(token?.variants[0].keys == [letter])
        #expect(token?.variants[0].boundary == ". ")
        #expect(token?.variants[1].keys == [letter, punctuation])
        #expect(token?.variants[1].boundary == " ")
        #expect(token?.deletionCount == 3)
    }

    @Test func backspaceReopensRecentWord() {
        var state = TypingStateMachine()
        let key = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        _ = state.consume(key: key, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1)
        _ = state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ",
            alternateCharacter: " ",
            context: context,
            timestamp: 2
        )
        state.backspace(timestamp: 3)
        #expect(state.activeKeys == [key])
    }
}
