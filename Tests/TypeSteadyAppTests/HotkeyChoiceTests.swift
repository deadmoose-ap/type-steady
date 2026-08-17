import Carbon
import Testing
@testable import TypeSteadyApp

struct HotkeyChoiceTests {
    @Test func optionSpacePreset() {
        #expect(HotkeyChoice.optionSpace.carbonModifiers == UInt32(optionKey))
        #expect(HotkeyChoice.optionSpace.selectionCarbonModifiers == UInt32(optionKey | cmdKey))
        #expect(HotkeyChoice.optionSpace.title == "⌥Space")
        #expect(HotkeyChoice.optionSpace.selectionTitle == "⌘⌥Space")
    }

    @Test func storedRawValuesRemainStable() {
        #expect(HotkeyChoice(rawValue: 0) == .controlOptionSpace)
        #expect(HotkeyChoice(rawValue: 1) == .controlShiftSpace)
        #expect(HotkeyChoice(rawValue: 2) == .commandOptionSpace)
        #expect(HotkeyChoice(rawValue: 3) == .optionSpace)
    }

    @Test func everyPresetHasDistinctBaseAndDerivedSelectionShortcut() {
        for choice in HotkeyChoice.allCases {
            #expect(choice.carbonModifiers != choice.selectionCarbonModifiers)
            #expect(choice.selectionCarbonModifiers & UInt32(cmdKey) != 0)
            #expect(!choice.title.isEmpty)
            #expect(!choice.selectionTitle.isEmpty)
        }
    }
}
