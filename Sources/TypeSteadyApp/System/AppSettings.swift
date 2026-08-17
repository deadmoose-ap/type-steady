import AppKit
import Carbon
import Combine
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
    case optionSpace = 3
    case controlOptionSpace = 0
    case controlShiftSpace = 1
    case commandOptionSpace = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .optionSpace: return "⌥Space"
        case .controlOptionSpace: return "⌃⌥Space"
        case .controlShiftSpace: return "⌃⇧Space"
        case .commandOptionSpace: return "⌘⌥Space"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionSpace: return UInt32(optionKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .controlShiftSpace: return UInt32(controlKey | shiftKey)
        case .commandOptionSpace: return UInt32(cmdKey | optionKey)
        }
    }

    var selectionCarbonModifiers: UInt32 {
        if carbonModifiers & UInt32(cmdKey) != 0 {
            return carbonModifiers | UInt32(controlKey)
        }
        return carbonModifiers | UInt32(cmdKey)
    }

    var selectionTitle: String {
        switch self {
        case .optionSpace: return "⌘⌥Space"
        case .controlOptionSpace: return "⌘⌃⌥Space"
        case .controlShiftSpace: return "⌘⌃⇧Space"
        case .commandOptionSpace: return "⌘⌃⌥Space"
        }
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
    @Published var englishLayoutID: String { didSet { persist(Key.englishLayoutID, englishLayoutID) } }
    @Published var russianLayoutID: String { didSet { persist(Key.russianLayoutID, russianLayoutID) } }
    @Published var excludedBundleIDs: String { didSet { persist(Key.excludedBundleIDs, excludedBundleIDs) } }
    @Published var alwaysConvert: String { didSet { persist(Key.alwaysConvert, alwaysConvert) } }
    @Published var neverConvert: String {
        didSet {
            neverCorrectRules = UserTermRules(neverConvert)
            persist(Key.neverConvert, neverConvert)
        }
    }
    private(set) var neverCorrectRules: UserTermRules

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
        excludedBundleIDs = defaults.string(forKey: Key.excludedBundleIDs) ?? ""
        alwaysConvert = defaults.string(forKey: Key.alwaysConvert) ?? ""
        let storedNeverConvert = defaults.string(forKey: Key.neverConvert) ?? ""
        neverConvert = storedNeverConvert
        neverCorrectRules = UserTermRules(storedNeverConvert)
    }

    var excludedBundleIDSet: Set<String> { lineSet(excludedBundleIDs) }
    var alwaysConvertSet: Set<String> { lineSet(alwaysConvert) }
    var neverConvertSet: Set<String> { neverCorrectRules.entries }

    private func lineSet(_ source: String) -> Set<String> {
        Set(source
            .components(separatedBy: .newlines)
            .map(UserTermRules.normalize)
            .filter { !$0.isEmpty })
    }

    private func persist(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .typeSteadySettingsChanged, object: self)
    }
}
