import Foundation
import Testing
@testable import TypeSteadyApp

@MainActor
struct AppSettingsTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "TypeSteady.AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func usesDocumentedDefaults() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.isEnabled)
        #expect(settings.automaticCorrection)
        #expect(settings.selectionConversion)
        #expect(settings.transliteration)
        #expect(settings.strictCodeEditors)
        #expect(settings.aggressiveness == .maximum)
        #expect(settings.manualHotkey == .controlOptionSpace)
        #expect(!settings.diagnostics)
    }

    @Test func persistsEveryUserFacingValue() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.isEnabled = false
        settings.automaticCorrection = false
        settings.selectionConversion = false
        settings.transliteration = false
        settings.soundFeedback = false
        settings.visualFeedback = false
        settings.diagnostics = true
        settings.strictCodeEditors = false
        settings.aggressiveness = .conservative
        settings.manualHotkey = .controlShiftSpace
        settings.englishLayoutID = "en.test"
        settings.russianLayoutID = "ru.test"
        settings.excludedBundleIDs = "COM.EXAMPLE.APP"
        settings.alwaysConvert = "  GHBDTN  "
        settings.neverConvert = "TypeSteady special"

        let restored = AppSettings(defaults: defaults)
        #expect(!restored.isEnabled)
        #expect(!restored.automaticCorrection)
        #expect(!restored.selectionConversion)
        #expect(!restored.transliteration)
        #expect(!restored.soundFeedback)
        #expect(!restored.visualFeedback)
        #expect(restored.diagnostics)
        #expect(!restored.strictCodeEditors)
        #expect(restored.aggressiveness == .conservative)
        #expect(restored.manualHotkey == .controlShiftSpace)
        #expect(restored.englishLayoutID == "en.test")
        #expect(restored.russianLayoutID == "ru.test")
        #expect(restored.excludedBundleIDSet == ["com.example.app"])
        #expect(restored.alwaysConvertSet == ["ghbdtn"])
        #expect(restored.neverCorrectRules.contains("special"))
    }

    @Test func postsSettingsChangeNotification() async {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        await confirmation("settings changed") { confirmed in
            let observer = NotificationCenter.default.addObserver(
                forName: .typeSteadySettingsChanged,
                object: settings,
                queue: nil
            ) { _ in confirmed() }
            settings.visualFeedback.toggle()
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // H1/[RAW]: пользователи, у которых в UserDefaults сохранено rawValue 3 (удалённый
    // пресет optionSpace), должны откатиться на дефолт .controlOptionSpace, а не крашнуться
    // и не получить неопределённый выбор — HotkeyChoice(rawValue: 3) возвращает nil, и
    // `?? .controlOptionSpace` в AppSettings.init обязан это покрывать.
    @Test func migratesRemovedOptionSpaceRawValueToDefault() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(3, forKey: "manualHotkey")

        #expect(HotkeyChoice(rawValue: 3) == nil)

        let settings = AppSettings(defaults: defaults)
        #expect(settings.manualHotkey == .controlOptionSpace)
    }

    @Test func aggressivenessMarginsAreOrdered() {
        #expect(DetectionAggressiveness.conservative.minimumMargin > DetectionAggressiveness.balanced.minimumMargin)
        #expect(DetectionAggressiveness.balanced.minimumMargin > DetectionAggressiveness.maximum.minimumMargin)
    }
}
