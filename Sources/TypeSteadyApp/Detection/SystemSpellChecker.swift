import AppKit

@MainActor
protocol SystemSpellChecking {
    func isKnown(_ word: String, language: LanguageCode) -> Bool
}

@MainActor
struct SystemSpellChecker: SystemSpellChecking {
    func isKnown(_ word: String, language: LanguageCode) -> Bool {
        guard word.count > 1 else { return false }
        let preferred = language == .english ? "en_US" : "ru_RU"
        let available = NSSpellChecker.shared.availableLanguages
        let resolvedLanguage = available.first(where: { $0 == preferred })
            ?? available.first(where: { $0.lowercased().hasPrefix(language.rawValue) })
            ?? language.rawValue
        let range = NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: resolvedLanguage,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }
}

@MainActor
struct NullSpellChecker: SystemSpellChecking {
    func isKnown(_ word: String, language: LanguageCode) -> Bool { false }
}
