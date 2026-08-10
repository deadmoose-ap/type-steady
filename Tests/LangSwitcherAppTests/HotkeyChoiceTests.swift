import Carbon
import Testing
@testable import LangSwitcherApp

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
}
