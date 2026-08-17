import CoreGraphics
import Testing
@testable import TypeSteadyApp

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

    @Test func punctuationCompletesWordAndKeepsBoundary() {
        var state = TypingStateMachine()
        let letter = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        _ = state.consume(key: letter, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1)
        let token = state.consume(
            key: PhysicalKey(keyCode: 43, shift: true, capsLock: false),
            currentCharacter: ",",
            alternateCharacter: ",",
            context: context,
            timestamp: 2
        )
        #expect(token?.variants.first?.boundary == ",")
        #expect(token?.deletionCount == 2)
    }

    @Test func flushesAmbiguousPunctuation() {
        var state = TypingStateMachine()
        let letter = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        _ = state.consume(key: letter, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1)
        _ = state.consume(
            key: PhysicalKey(keyCode: 47, shift: false, capsLock: false),
            currentCharacter: ".",
            alternateCharacter: "ю",
            context: context,
            timestamp: 2
        )

        #expect(state.hasPendingAmbiguousKey)
        let token = state.flushAmbiguous(timestamp: 3)
        #expect(token?.variants.first?.boundary == ".")
        #expect(!state.hasPendingAmbiguousKey)
    }

    @Test func nextLetterAbsorbsAmbiguousKeyIntoWord() {
        var state = TypingStateMachine()
        let first = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        let ambiguous = PhysicalKey(keyCode: 47, shift: false, capsLock: false)
        let last = PhysicalKey(keyCode: 5, shift: false, capsLock: false)
        _ = state.consume(key: first, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1)
        _ = state.consume(key: ambiguous, currentCharacter: ".", alternateCharacter: "ю", context: context, timestamp: 2)
        _ = state.consume(key: last, currentCharacter: "b", alternateCharacter: "и", context: context, timestamp: 3)
        let token = state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ", alternateCharacter: " ", context: context, timestamp: 4
        )

        #expect(token?.variants.first?.keys == [first, ambiguous, last])
    }

    @Test func contextChangeDiscardsPreviousPartialWord() {
        var state = TypingStateMachine()
        let first = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        let second = PhysicalKey(keyCode: 5, shift: false, capsLock: false)
        _ = state.consume(key: first, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1)
        let other = AppContext(processIdentifier: 43, bundleIdentifier: "other.editor")
        _ = state.consume(key: second, currentCharacter: "b", alternateCharacter: "и", context: other, timestamp: 2)
        let token = state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ", alternateCharacter: " ", context: other, timestamp: 3
        )

        #expect(token?.variants.first?.keys == [second])
    }

    @Test func staleBackspaceDoesNotReopenCompletedWord() {
        var state = TypingStateMachine()
        let key = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        _ = state.consume(key: key, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1)
        _ = state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ", alternateCharacter: " ", context: context, timestamp: 2
        )
        state.backspace(timestamp: 8)
        #expect(state.activeKeys.isEmpty)
        #expect(state.lastCompleted == nil)
    }

    @Test func apostropheAndHyphenRemainInsideWord() {
        var state = TypingStateMachine()
        let keys = (1...5).map { PhysicalKey(keyCode: UInt16($0), shift: false, capsLock: false) }
        let characters = ["a", "'", "b", "-", "c"]
        for (key, character) in zip(keys, characters) {
            #expect(state.consume(
                key: key, currentCharacter: character, alternateCharacter: character,
                context: context, timestamp: Double(key.keyCode)
            ) == nil)
        }
        let token = state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ", alternateCharacter: " ", context: context, timestamp: 6
        )
        #expect(token?.variants.first?.keys == keys)
    }

    @Test func mouseStyleInvalidationCanPreserveOrDiscardLastToken() {
        var state = TypingStateMachine()
        let key = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        _ = state.consume(key: key, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1)
        _ = state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ", alternateCharacter: " ", context: context, timestamp: 2
        )
        state.invalidate(preserveLast: true)
        #expect(state.lastCompleted != nil)
        state.invalidate()
        #expect(state.lastCompleted == nil)
    }
}
