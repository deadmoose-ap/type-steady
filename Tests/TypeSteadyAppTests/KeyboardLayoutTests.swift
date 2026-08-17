import Testing
@testable import TypeSteadyApp

struct KeyboardLayoutTests {
    @Test func descriptorRecognizesSupportedLanguages() {
        #expect(LayoutDescriptor(id: "en", name: "ABC", languages: ["en-US"]).languageCode == .english)
        #expect(LayoutDescriptor(id: "ru", name: "Русская", languages: ["ru"]).languageCode == .russian)
        #expect(LayoutDescriptor(id: "de", name: "German", languages: ["de"]).languageCode == nil)
    }

    @Test func snapshotRendersAndReverseMapsPhysicalKeys() {
        let plain = PhysicalKey(keyCode: 1, shift: false, capsLock: false)
        let shifted = PhysicalKey(keyCode: 1, shift: true, capsLock: false)
        let second = PhysicalKey(keyCode: 2, shift: false, capsLock: false)
        let layout = KeyboardLayoutSnapshot.testLayout(
            id: "en", name: "English", language: .english,
            characters: [plain: "a", shifted: "A", second: "b"]
        )

        #expect(layout.character(for: shifted) == "A")
        #expect(layout.physicalKey(for: "a") == plain)
        #expect(layout.render([plain, second]) == "ab")
        #expect(layout.render([PhysicalKey(keyCode: 99, shift: false, capsLock: false)]) == nil)
    }

    @Test func reverseMapPrefersUnmodifiedKey() {
        let plain = PhysicalKey(keyCode: 1, shift: false, capsLock: false)
        let modified = PhysicalKey(keyCode: 2, shift: true, capsLock: true)
        let layout = KeyboardLayoutSnapshot.testLayout(
            id: "en", name: "English", language: .english,
            characters: [modified: "x", plain: "x"]
        )
        #expect(layout.physicalKey(for: "x") == plain)
    }
}
