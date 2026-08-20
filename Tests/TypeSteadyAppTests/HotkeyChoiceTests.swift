import Carbon
import Testing
@testable import TypeSteadyApp

struct HotkeyChoiceTests {
    @Test func storedRawValuesRemainStable() {
        #expect(HotkeyChoice(rawValue: 0) == .controlOptionSpace)
        #expect(HotkeyChoice(rawValue: 1) == .controlShiftSpace)
        #expect(HotkeyChoice(rawValue: 2) == .commandOptionSpace)
        #expect(HotkeyChoice(rawValue: 4) == .optionOnly)
    }

    // H1/[RAW]: rawValue 3 принадлежал удалённому пресету optionSpace (⌥Space, зарезервирован
    // системой за Gemini) и никогда не переиспользуется. HotkeyChoice(rawValue: 3) обязан
    // возвращать nil, а AppSettings.init обязан откатывать таких пользователей на дефолт —
    // проверено отдельно в AppSettingsTests.migratesRemovedOptionSpaceRawValueToDefault.
    @Test func removedOptionSpaceRawValueNoLongerResolves() {
        #expect(HotkeyChoice(rawValue: 3) == nil)
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

    // D6: закрепляет намеренное (см. комментарий над HotkeyChoice.matches) поведение —
    // .optionOnly не совпадает НИ С ЧЕМ через matches(keyCode:flags:), включая Option+любая
    // буква, а не только "случайные" сочетания. everyPresetMatchesOnlyItsExactShortcut выше
    // проверяет это как частный случай общего цикла; здесь — явно и по имени.
    @Test func optionOnlyNeverMatchesKeyCodeAndFlagsCombination() {
        #expect(!HotkeyChoice.optionOnly.matches(keyCode: UInt16(kVK_Space), flags: [.maskAlternate]))
        #expect(!HotkeyChoice.optionOnly.matches(keyCode: UInt16(kVK_ANSI_A), flags: [.maskAlternate]))
        #expect(!HotkeyChoice.optionOnly.matches(keyCode: UInt16(kVK_ANSI_A), flags: []))
    }

    @Test func shiftPresetIncludesShiftInEventTapMatching() {
        #expect(HotkeyChoice.controlShiftSpace.eventFlags == [.maskControl, .maskShift])
        #expect(HotkeyChoice.controlShiftSpace.matches(
            keyCode: UInt16(kVK_Space),
            flags: [.maskControl, .maskShift]
        ))
    }
}
