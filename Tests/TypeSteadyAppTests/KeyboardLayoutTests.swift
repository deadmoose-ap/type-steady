import Foundation
import Testing
@testable import TypeSteadyApp

@MainActor
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

    // D4: LayoutCatalog.refresh() присваивает settings.englishLayoutID/russianLayoutID,
    // что раньше (до B8) синхронно постило .typeSteadySettingsChanged и синхронно
    // вызывало AppDelegate.applySettings() ИЗНУТРИ refresh() — реентерабельность. Тест
    // не поднимает реальный LayoutCatalog/TIS (недетерминированно на разных машинах) —
    // проверяет напрямую то самое условие, которое снимает проблему: присваивание
    // englishLayoutID/russianLayoutID НЕ постит уведомление синхронно, только с задержкой
    // (persistDebounced, ~150 мс). Пока это так, независимо от того, кто присваивает
    // значение, реентерабельного синхронного вызова applySettings() не будет.
    @Test func layoutIDAssignmentDoesNotPostNotificationSynchronously() async {
        let name = "TypeSteady.KeyboardLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)

        var notified = false
        let observer = NotificationCenter.default.addObserver(
            forName: .typeSteadySettingsChanged,
            object: settings,
            queue: nil
        ) { _ in notified = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        settings.englishLayoutID = "en.test"
        settings.russianLayoutID = "ru.test"

        // Сразу после присваивания уведомление ещё не должно было прийти — оно
        // дебаунсится на ~150 мс, а не постится синхронно из didSet.
        #expect(!notified)
    }
}
