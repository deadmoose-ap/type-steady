import AppKit
import Carbon
import Combine
import CoreGraphics
import Foundation

enum DetectionAggressiveness: Int, CaseIterable, Identifiable {
    case conservative
    case balanced
    case maximum

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .conservative: return "Осторожно"
        case .balanced: return "Сбалансированно"
        case .maximum: return "Максимальное покрытие"
        }
    }

    var minimumMargin: Double {
        switch self {
        case .conservative: return 4.0
        case .balanced: return 2.6
        case .maximum: return 1.4
        }
    }
}

enum HotkeyChoice: Int, CaseIterable, Identifiable {
    // Explicit raw values preserve already stored choices when new presets are added.
    // [RAW] raw value 3 навсегда выведено из обращения: ранее принадлежало пресету
    // optionSpace (⌥Space), удалённому в H1 — комбинация зарезервирована в системе за
    // вызовом Gemini. Пользователи с сохранённым rawValue 3 откатываются на дефолт
    // .controlOptionSpace через `?? .controlOptionSpace` в AppSettings.init. Никогда не
    // переиспользовать 3 для нового пресета.
    case optionOnly = 4
    case controlOptionSpace = 0
    case controlShiftSpace = 1
    case commandOptionSpace = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .optionOnly: return "⌥ Option"
        case .controlOptionSpace: return "⌃⌥Space"
        case .controlShiftSpace: return "⌃⇧Space"
        case .commandOptionSpace: return "⌘⌥Space"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionOnly: return UInt32(optionKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .controlShiftSpace: return UInt32(controlKey | shiftKey)
        case .commandOptionSpace: return UInt32(cmdKey | optionKey)
        }
    }

    var eventFlags: CGEventFlags {
        switch self {
        case .optionOnly: return [.maskAlternate]
        case .controlOptionSpace: return [.maskControl, .maskAlternate]
        case .controlShiftSpace: return [.maskControl, .maskShift]
        case .commandOptionSpace: return [.maskCommand, .maskAlternate]
        }
    }

    var carbonKeyCode: UInt32? {
        self == .optionOnly ? nil : UInt32(kVK_Space)
    }

    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard let carbonKeyCode else { return false }
        let modifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        return keyCode == UInt16(carbonKeyCode) && modifiers == eventFlags
    }
}

extension Notification.Name {
    static let typeSteadySettingsChanged = Notification.Name("TypeSteadySettingsChanged")
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let automatic = "automatic"
        static let selection = "selection"
        static let transliteration = "transliteration"
        static let sound = "sound"
        static let visual = "visual"
        static let diagnostics = "diagnostics"
        static let strictCodeEditors = "strictCodeEditors"
        static let aggressiveness = "aggressiveness"
        static let manualHotkey = "manualHotkey"
        static let englishLayoutID = "englishLayoutID"
        static let russianLayoutID = "russianLayoutID"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let alwaysConvert = "alwaysConvert"
        static let neverConvert = "neverConvert"
    }

    private let defaults: UserDefaults

    @Published var isEnabled: Bool { didSet { persist(Key.enabled, isEnabled) } }
    @Published var automaticCorrection: Bool { didSet { persist(Key.automatic, automaticCorrection) } }
    @Published var selectionConversion: Bool { didSet { persist(Key.selection, selectionConversion) } }
    @Published var transliteration: Bool { didSet { persist(Key.transliteration, transliteration) } }
    @Published var soundFeedback: Bool { didSet { persist(Key.sound, soundFeedback) } }
    @Published var visualFeedback: Bool { didSet { persist(Key.visual, visualFeedback) } }
    @Published var diagnostics: Bool { didSet { persist(Key.diagnostics, diagnostics) } }
    @Published var strictCodeEditors: Bool { didSet { persist(Key.strictCodeEditors, strictCodeEditors) } }
    @Published var aggressiveness: DetectionAggressiveness { didSet { persist(Key.aggressiveness, aggressiveness.rawValue) } }
    @Published var manualHotkey: HotkeyChoice { didSet { persist(Key.manualHotkey, manualHotkey.rawValue) } }
    // B8: у строковых свойств набор символов меняется на каждое нажатие клавиши в
    // текстовом поле настроек — рассылка .typeSteadySettingsChanged (и, соответственно,
    // applySettings() у AppDelegate) для них дебаунсится на ~150 мс. Булевы/enum-свойства
    // выше продолжают постить немедленно — от них зависят пуск/остановка event tap и
    // перерегистрация хоткея, задержка там недопустима.
    @Published var englishLayoutID: String { didSet { persistDebounced(Key.englishLayoutID, englishLayoutID) } }
    @Published var russianLayoutID: String { didSet { persistDebounced(Key.russianLayoutID, russianLayoutID) } }
    @Published var excludedBundleIDs: String {
        didSet {
            // B4: кэш пересобирается немедленно и синхронно с самим значением — дебаунсится
            // только рассылка уведомления ниже, а не сам кэш, иначе только что введённое
            // правило не действовало бы ближайшие 150 мс.
            excludedBundleIDSet = lineSet(excludedBundleIDs)
            persistDebounced(Key.excludedBundleIDs, excludedBundleIDs)
        }
    }
    @Published var alwaysConvert: String {
        didSet {
            alwaysConvertSet = lineSet(alwaysConvert)
            persistDebounced(Key.alwaysConvert, alwaysConvert)
        }
    }
    @Published var neverConvert: String {
        didSet {
            neverCorrectRules = UserTermRules(neverConvert)
            persistDebounced(Key.neverConvert, neverConvert)
        }
    }
    private(set) var neverCorrectRules: UserTermRules
    // B4: были вычисляемыми свойствами (lineSet прогоняет каждую строку через
    // UserTermRules.normalize) и пересчитывались на каждое нажатие клавиши — excludedBundleIDSet
    // читается в InputCoordinator.handle()/DetectionEngine.proposal() на каждый keyDown,
    // alwaysConvertSet — на каждый завершённый токен. Теперь кэшируются в didSet, тем же
    // паттерном, что и neverConvert → neverCorrectRules выше.
    private(set) var excludedBundleIDSet: Set<String>
    private(set) var alwaysConvertSet: Set<String>
    private var pendingNotification: DispatchWorkItem?
    private static let stringPropertyNotificationDebounce: TimeInterval = 0.15

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        automaticCorrection = defaults.object(forKey: Key.automatic) as? Bool ?? true
        selectionConversion = defaults.object(forKey: Key.selection) as? Bool ?? true
        transliteration = defaults.object(forKey: Key.transliteration) as? Bool ?? true
        soundFeedback = defaults.object(forKey: Key.sound) as? Bool ?? true
        visualFeedback = defaults.object(forKey: Key.visual) as? Bool ?? true
        diagnostics = defaults.object(forKey: Key.diagnostics) as? Bool ?? false
        strictCodeEditors = defaults.object(forKey: Key.strictCodeEditors) as? Bool ?? true
        if defaults.object(forKey: Key.aggressiveness) == nil {
            aggressiveness = .maximum
        } else {
            aggressiveness = DetectionAggressiveness(rawValue: defaults.integer(forKey: Key.aggressiveness)) ?? .maximum
        }
        manualHotkey = HotkeyChoice(rawValue: defaults.integer(forKey: Key.manualHotkey)) ?? .controlOptionSpace
        englishLayoutID = defaults.string(forKey: Key.englishLayoutID) ?? ""
        russianLayoutID = defaults.string(forKey: Key.russianLayoutID) ?? ""
        let storedExcludedBundleIDs = defaults.string(forKey: Key.excludedBundleIDs) ?? ""
        excludedBundleIDs = storedExcludedBundleIDs
        let storedAlwaysConvert = defaults.string(forKey: Key.alwaysConvert) ?? ""
        alwaysConvert = storedAlwaysConvert
        let storedNeverConvert = defaults.string(forKey: Key.neverConvert) ?? ""
        neverConvert = storedNeverConvert
        neverCorrectRules = UserTermRules(storedNeverConvert)
        // Кэши инициализируются здесь напрямую (а не через didSet выше — didSet не
        // выполняется при первичном присваивании в init) тем же способом, что и
        // neverCorrectRules двумя строками выше.
        excludedBundleIDSet = Self.lineSet(storedExcludedBundleIDs)
        alwaysConvertSet = Self.lineSet(storedAlwaysConvert)
    }

    var neverConvertSet: Set<String> { neverCorrectRules.entries }

    private func lineSet(_ source: String) -> Set<String> {
        Self.lineSet(source)
    }

    private static func lineSet(_ source: String) -> Set<String> {
        Set(source
            .components(separatedBy: .newlines)
            .map(UserTermRules.normalize)
            .filter { !$0.isEmpty })
    }

    private func persist(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .typeSteadySettingsChanged, object: self)
    }

    /// B8: значение в UserDefaults записывается немедленно (чтение настроек не должно
    /// зависеть от таймера), а рассылка уведомления об изменении — дебаунсится, чтобы
    /// applySettings() у AppDelegate не перезапускался на каждый символ, набранный в
    /// текстовом поле «Исключённые приложения»/«Всегда/Никогда исправлять».
    private func persistDebounced(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        pendingNotification?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: .typeSteadySettingsChanged, object: self)
        }
        pendingNotification = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stringPropertyNotificationDebounce, execute: work)
    }
}
