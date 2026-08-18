import Carbon
import Testing
@testable import TypeSteadyApp

struct HotkeyChoiceTests {
    @Test func optionSpacePreset() {
        #expect(HotkeyChoice.optionSpace.carbonModifiers == UInt32(optionKey))
        #expect(HotkeyChoice.optionSpace.eventFlags == [.maskAlternate])
        #expect(HotkeyChoice.optionSpace.title == "⌥Space")
        #expect(HotkeyChoice.optionSpace.matches(keyCode: UInt16(kVK_Space), flags: [.maskAlternate]))
    }

    @Test func storedRawValuesRemainStable() {
        #expect(HotkeyChoice(rawValue: 0) == .controlOptionSpace)
        #expect(HotkeyChoice(rawValue: 1) == .controlShiftSpace)
        #expect(HotkeyChoice(rawValue: 2) == .commandOptionSpace)
        #expect(HotkeyChoice(rawValue: 3) == .optionSpace)
        #expect(HotkeyChoice(rawValue: 4) == .optionOnly)
    }

    @Test func everyPresetMatchesOnlyItsExactShortcut() {
        for choice in HotkeyChoice.allCases {
            #expect(!choice.title.isEmpty)
            guard choice.carbonKeyCode != nil else {
                #expect(!choice.matches(keyCode: UInt16(kVK_Space), flags: choice.eventFlags))
                continue
            }
            #expect(choice.matches(keyCode: UInt16(kVK_Space), flags: choice.eventFlags))
            #expect(!choice.matches(keyCode: UInt16(kVK_ANSI_A), flags: choice.eventFlags))
            #expect(choice.matches(keyCode: UInt16(kVK_Space), flags: choice.eventFlags.union(.maskAlphaShift)))
            for other in HotkeyChoice.allCases where other != choice && other.carbonKeyCode != nil && other.eventFlags != choice.eventFlags {
                #expect(!choice.matches(keyCode: UInt16(kVK_Space), flags: other.eventFlags))
            }
        }
    }

    @Test func optionOnlyUsesEventTapInsteadOfInvalidCarbonRegistration() {
        #expect(HotkeyChoice.optionOnly.title == "⌥ Option")
        #expect(HotkeyChoice.optionOnly.carbonKeyCode == nil)
        #expect(HotkeyChoice.optionOnly.eventFlags == [.maskAlternate])
    }

    @Test func shiftPresetIncludesShiftInEventTapMatching() {
        #expect(HotkeyChoice.controlShiftSpace.eventFlags == [.maskControl, .maskShift])
        #expect(HotkeyChoice.controlShiftSpace.matches(
            keyCode: UInt16(kVK_Space),
            flags: [.maskControl, .maskShift]
        ))
    }
}
