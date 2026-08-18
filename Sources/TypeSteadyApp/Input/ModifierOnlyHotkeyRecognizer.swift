import CoreGraphics

struct ModifierOnlyHotkeyRecognizer {
    private var optionIsArmed = false

    mutating func consume(_ event: InputEventSnapshot, enabled: Bool) -> Bool {
        guard enabled else {
            reset()
            return false
        }

        if event.type == .flagsChanged {
            let modifiers = event.flags.intersection([
                .maskCommand, .maskControl, .maskAlternate, .maskShift
            ])
            if modifiers == [.maskAlternate] {
                optionIsArmed = true
                return false
            }
            if modifiers.isEmpty, optionIsArmed {
                optionIsArmed = false
                return true
            }
            optionIsArmed = false
            return false
        }

        if event.type == .keyDown || event.type == .leftMouseDown ||
            event.type == .rightMouseDown || event.type == .otherMouseDown {
            optionIsArmed = false
        }
        return false
    }

    mutating func reset() {
        optionIsArmed = false
    }
}
