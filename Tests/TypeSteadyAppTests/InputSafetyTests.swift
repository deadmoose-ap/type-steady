import Carbon
import CoreGraphics
import Testing
@testable import TypeSteadyApp

struct InputSafetyTests {
    @Test func permissionRevocationStopsInsteadOfRepeatedlyNotifying() {
        var policy = InputEventTapDisablePolicy()

        let first = policy.notification(for: .tapDisabledByUserInput)
        let repeated = policy.notification(for: .tapDisabledByUserInput)
        let differentRepeat = policy.notification(for: .tapDisabledByTimeout)
        #expect(first == .permissionOrUserInput)
        #expect(repeated == nil)
        #expect(differentRepeat == nil)

        policy.reset()
        let afterReset = policy.notification(for: .tapDisabledByTimeout)
        #expect(afterReset == .timeout)
    }

    @Test func ordinaryEventsDoNotConsumeDisableNotification() {
        var policy = InputEventTapDisablePolicy()
        let ordinary = policy.notification(for: .keyDown)
        let disabled = policy.notification(for: .tapDisabledByUserInput)
        #expect(ordinary == nil)
        #expect(disabled == .permissionOrUserInput)
    }

    @Test func optionOnlyTriggersOnCleanRelease() {
        var recognizer = ModifierOnlyHotkeyRecognizer()

        let armed = recognizer.consume(snapshot(type: .flagsChanged, flags: [.maskAlternate]), enabled: true)
        let released = recognizer.consume(snapshot(type: .flagsChanged, flags: []), enabled: true)
        let repeatedRelease = recognizer.consume(snapshot(type: .flagsChanged, flags: []), enabled: true)
        #expect(!armed)
        #expect(released)
        #expect(!repeatedRelease)
    }

    @Test func optionOnlyCancelsWhenAnotherKeyIsPressed() {
        var recognizer = ModifierOnlyHotkeyRecognizer()

        let armed = recognizer.consume(snapshot(type: .flagsChanged, flags: [.maskAlternate]), enabled: true)
        let keyPressed = recognizer.consume(
            snapshot(type: .keyDown, keyCode: UInt16(kVK_ANSI_A), flags: [.maskAlternate]),
            enabled: true
        )
        let released = recognizer.consume(snapshot(type: .flagsChanged, flags: []), enabled: true)
        #expect(!armed)
        #expect(!keyPressed)
        #expect(!released)
    }

    @Test func optionOnlyCancelsWhenCombinedWithAnotherModifier() {
        var recognizer = ModifierOnlyHotkeyRecognizer()

        let armed = recognizer.consume(snapshot(type: .flagsChanged, flags: [.maskAlternate]), enabled: true)
        let combined = recognizer.consume(
            snapshot(type: .flagsChanged, flags: [.maskAlternate, .maskCommand]),
            enabled: true
        )
        let released = recognizer.consume(snapshot(type: .flagsChanged, flags: []), enabled: true)
        #expect(!armed)
        #expect(!combined)
        #expect(!released)
    }

    @Test func disabledOptionOnlyNeverTriggers() {
        var recognizer = ModifierOnlyHotkeyRecognizer()

        let pressed = recognizer.consume(snapshot(type: .flagsChanged, flags: [.maskAlternate]), enabled: false)
        let released = recognizer.consume(snapshot(type: .flagsChanged, flags: []), enabled: false)
        #expect(!pressed)
        #expect(!released)
    }

    private func snapshot(
        type: CGEventType,
        keyCode: UInt16 = UInt16(kVK_Option),
        flags: CGEventFlags
    ) -> InputEventSnapshot {
        InputEventSnapshot(
            type: type,
            keyCode: keyCode,
            flags: flags,
            isRepeat: false,
            timestamp: 1
        )
    }
}
