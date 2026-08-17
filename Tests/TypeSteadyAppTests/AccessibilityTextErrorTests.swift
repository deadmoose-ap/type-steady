import Testing
@testable import TypeSteadyApp

struct AccessibilityTextErrorTests {
    @Test func exposesActionableLocalizedDescriptions() {
        let cases: [AccessibilityTextError] = [
            .permissionMissing, .noFocusedElement, .secureField,
            .noSelection, .replacementUnsupported, .applicationChanged
        ]
        for error in cases {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
        #expect(AccessibilityTextError.permissionMissing.errorDescription?.contains("Accessibility") == true)
        #expect(AccessibilityTextError.secureField.errorDescription == "Защищённое поле")
    }
}
