import Carbon
import Combine
import Foundation

struct LayoutDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let languages: [String]

    var languageCode: LanguageCode? {
        if languages.contains(where: { $0.lowercased().hasPrefix("ru") }) { return .russian }
        if languages.contains(where: { $0.lowercased().hasPrefix("en") }) { return .english }
        return nil
    }
}

struct KeyboardLayoutSnapshot: Sendable {
    let descriptor: LayoutDescriptor
    private let characters: [PhysicalKey: String]
    private let reverseCharacters: [String: PhysicalKey]

    init(descriptor: LayoutDescriptor, characters: [PhysicalKey: String]) {
        self.descriptor = descriptor
        self.characters = characters

        var reverse: [String: PhysicalKey] = [:]
        for (key, value) in characters where !value.isEmpty {
            if let existing = reverse[value] {
                let existingRank = (existing.shift ? 1 : 0) + (existing.capsLock ? 2 : 0)
                let newRank = (key.shift ? 1 : 0) + (key.capsLock ? 2 : 0)
                if newRank < existingRank { reverse[value] = key }
            } else {
                reverse[value] = key
            }
        }
        reverseCharacters = reverse
    }

    func character(for key: PhysicalKey) -> String? {
        characters[key]
    }

    func physicalKey(for character: Character) -> PhysicalKey? {
        reverseCharacters[String(character)]
    }

    func render(_ keys: [PhysicalKey]) -> String? {
        var result = ""
        result.reserveCapacity(keys.count)
        for key in keys {
            guard let character = characters[key] else { return nil }
            result.append(character)
        }
        return result
    }

    static func testLayout(
        id: String,
        name: String,
        language: LanguageCode,
        characters: [PhysicalKey: String]
    ) -> KeyboardLayoutSnapshot {
        KeyboardLayoutSnapshot(
            descriptor: LayoutDescriptor(id: id, name: name, languages: [language.rawValue]),
            characters: characters
        )
    }
}

struct ActiveLayoutPair: Sendable {
    let source: KeyboardLayoutSnapshot
    let target: KeyboardLayoutSnapshot

    var sourceLanguage: LanguageCode { source.descriptor.languageCode ?? .english }
    var targetLanguage: LanguageCode { target.descriptor.languageCode ?? .russian }
}

@MainActor
final class LayoutCatalog: ObservableObject {
    @Published private(set) var descriptors: [LayoutDescriptor] = []
    @Published private(set) var lastError: String?

    private var sourcesByID: [String: TISInputSource] = [:]
    private var snapshotsByID: [String: KeyboardLayoutSnapshot] = [:]

    func refresh(settings: AppSettings) {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String
        ] as CFDictionary

        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            lastError = "Не удалось получить установленные раскладки"
            return
        }

        var newSources: [String: TISInputSource] = [:]
        var newSnapshots: [String: KeyboardLayoutSnapshot] = [:]
        var newDescriptors: [LayoutDescriptor] = []

        for source in sources {
            guard let id = stringProperty(source, kTISPropertyInputSourceID),
                  TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil else { continue }
            let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
            let languages = arrayProperty(source, kTISPropertyInputSourceLanguages)
            let descriptor = LayoutDescriptor(id: id, name: name, languages: languages)
            guard descriptor.languageCode != nil else { continue }
            guard let snapshot = buildSnapshot(source: source, descriptor: descriptor) else { continue }
            newSources[id] = source
            newSnapshots[id] = snapshot
            newDescriptors.append(descriptor)
        }

        newDescriptors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        sourcesByID = newSources
        snapshotsByID = newSnapshots
        descriptors = newDescriptors
        lastError = newDescriptors.isEmpty ? "English/Russian раскладки не найдены" : nil

        if settings.englishLayoutID.isEmpty || newSnapshots[settings.englishLayoutID] == nil {
            settings.englishLayoutID = preferredLayoutID(language: .english, descriptors: newDescriptors) ?? ""
        }
        if settings.russianLayoutID.isEmpty || newSnapshots[settings.russianLayoutID] == nil {
            settings.russianLayoutID = preferredLayoutID(language: .russian, descriptors: newDescriptors) ?? ""
        }
    }

    func selectedPair(settings: AppSettings) -> (english: KeyboardLayoutSnapshot, russian: KeyboardLayoutSnapshot)? {
        guard let english = snapshotsByID[settings.englishLayoutID],
              let russian = snapshotsByID[settings.russianLayoutID] else { return nil }
        return (english, russian)
    }

    func activePair(settings: AppSettings) -> ActiveLayoutPair? {
        guard let selected = selectedPair(settings: settings), let currentID = currentLayoutID() else { return nil }
        if currentID == selected.english.descriptor.id {
            return ActiveLayoutPair(source: selected.english, target: selected.russian)
        }
        if currentID == selected.russian.descriptor.id {
            return ActiveLayoutPair(source: selected.russian, target: selected.english)
        }
        return nil
    }

    func pair(from language: LanguageCode, settings: AppSettings) -> ActiveLayoutPair? {
        guard let selected = selectedPair(settings: settings) else { return nil }
        switch language {
        case .english: return ActiveLayoutPair(source: selected.english, target: selected.russian)
        case .russian: return ActiveLayoutPair(source: selected.russian, target: selected.english)
        }
    }

    func currentLayoutID() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return stringProperty(current, kTISPropertyInputSourceID)
    }

    /// B1: раньше поллинг подтверждения переключения раскладки крутился в плотном цикле
    /// `Thread.sleep` без единого оборота run loop — на MainActor это блокировало UI на
    /// весь таймаут (до 80 мс) и, по наблюдению пользователя, могло не успеть уложиться
    /// в 80 мс при коротком реальном окне ЦП. `Task.sleep` отпускает поток между
    /// проверками, run loop получает обороты — это одновременно снимает блокировку и,
    /// предположительно, чинит периодические отказы «Целевая раскладка недоступна» (см.
    /// отчёт по B1) — не подтверждено измерением на живой машине, отмечено как гипотеза.
    @discardableResult
    func selectLayout(id: String) async -> Bool {
        guard let source = sourcesByID[id] else { return false }
        guard TISSelectInputSource(source) == noErr else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.08
        repeat {
            if currentLayoutID() == id { return true }
            try? await Task.sleep(nanoseconds: 4_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return false
    }

    private func preferredLayoutID(language: LanguageCode, descriptors: [LayoutDescriptor]) -> String? {
        let candidates = descriptors.filter { $0.languageCode == language }
        switch language {
        case .english:
            return candidates.first(where: { $0.id.contains("ABC") })?.id ?? candidates.first?.id
        case .russian:
            return candidates.first(where: {
                $0.name.localizedCaseInsensitiveContains("Russian") &&
                !$0.name.localizedCaseInsensitiveContains("Phonetic") &&
                !$0.id.localizedCaseInsensitiveContains("Phonetic")
            })?.id ?? candidates.first?.id
        }
    }

    private func buildSnapshot(source: TISInputSource, descriptor: LayoutDescriptor) -> KeyboardLayoutSnapshot? {
        guard let dataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(dataRef).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())
        var map: [PhysicalKey: String] = [:]

        for keyCode: UInt16 in 0...127 {
            for shift in [false, true] {
                for capsLock in [false, true] {
                    let key = PhysicalKey(keyCode: keyCode, shift: shift, capsLock: capsLock)
                    if let character = translate(key, layoutData: data, keyboardType: keyboardType) {
                        map[key] = character
                    }
                }
            }
        }
        return KeyboardLayoutSnapshot(descriptor: descriptor, characters: map)
    }

    private func translate(_ key: PhysicalKey, layoutData: Data, keyboardType: UInt32) -> String? {
        var carbonModifiers: UInt32 = 0
        if key.shift { carbonModifiers |= UInt32(shiftKey) }
        if key.capsLock { carbonModifiers |= UInt32(alphaLock) }
        let modifierState = (carbonModifiers >> 8) & 0xFF
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var actualLength = 0

        let result = layoutData.withUnsafeBytes { bytes -> OSStatus in
            guard let address = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return errSecParam
            }
            return UCKeyTranslate(
                address,
                key.keyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                keyboardType,
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &actualLength,
                &characters
            )
        }

        guard result == noErr, actualLength > 0 else { return nil }
        let output = String(utf16CodeUnits: characters, count: actualLength)
        guard !output.isEmpty,
              !output.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return nil }
        return output
    }

    private func stringProperty(_ source: TISInputSource, _ property: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func arrayProperty(_ source: TISInputSource, _ property: CFString) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return [] }
        return Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
    }
}
