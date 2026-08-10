import Foundation

@MainActor
final class DetectionEngine {
    private let lexicon: LocalLexicon
    private let spellChecker: SystemSpellChecking
    private let transliterator = Transliterator()
    private let appPolicy = AppPolicy()

    init(lexicon: LocalLexicon, spellChecker: SystemSpellChecking) {
        self.lexicon = lexicon
        self.spellChecker = spellChecker
    }

    convenience init() {
        self.init(lexicon: LocalLexicon(), spellChecker: SystemSpellChecker())
    }

    func proposal(
        current: String,
        alternate: String,
        sourceLanguage: LanguageCode,
        targetLanguage: LanguageCode,
        context: AppContext,
        settings: AppSettings
    ) -> CorrectionProposal? {
        let normalizedCurrent = normalize(current)
        let normalizedAlternate = normalize(alternate)
        guard normalizedCurrent.count >= 2,
              normalizedCurrent != normalizedAlternate,
              !settings.neverConvertSet.contains(normalizedCurrent),
              !appPolicy.isHardDenied(bundleIdentifier: context.bundleIdentifier),
              !settings.excludedBundleIDSet.contains(context.bundleIdentifier.lowercased()) else { return nil }

        let codeEditor = settings.strictCodeEditors && appPolicy.isCodeEditor(bundleIdentifier: context.bundleIdentifier)
        guard !appPolicy.isStructurallyProtected(current, inCodeEditor: codeEditor) else { return nil }

        if settings.alwaysConvertSet.contains(normalizedCurrent) {
            return CorrectionProposal(
                original: current,
                replacement: alternate,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                confidence: 1,
                kind: .layout
            )
        }

        let currentScore = score(current, language: sourceLanguage)
        let alternateScore = score(alternate, language: targetLanguage)
        var requiredMargin = settings.aggressiveness.minimumMargin
        if codeEditor { requiredMargin += 2.4 }
        if current.count <= 2 { requiredMargin += 2.0 }

        if alternateScore - currentScore >= requiredMargin,
           alternateScore >= 4.0 {
            let confidence = confidenceFrom(margin: alternateScore - currentScore)
            return CorrectionProposal(
                original: current,
                replacement: alternate,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                confidence: confidence,
                kind: .layout
            )
        }

        guard settings.transliteration,
              sourceLanguage == .english,
              targetLanguage == .russian,
              currentScore < 5.0,
              current.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }

        let candidates = transliterator.candidates(for: current)
        let ranked = candidates
            .map { ($0, score($0, language: .russian)) }
            .sorted { $0.1 > $1.1 }
        guard let best = ranked.first,
              best.1 >= 5.0,
              best.1 - currentScore >= requiredMargin + 0.5 else { return nil }

        return CorrectionProposal(
            original: current,
            replacement: best.0,
            sourceLanguage: .english,
            targetLanguage: .russian,
            confidence: confidenceFrom(margin: best.1 - currentScore),
            kind: .transliteration
        )
    }

    func forcedProposal(
        current: String,
        alternate: String,
        sourceLanguage: LanguageCode,
        targetLanguage: LanguageCode
    ) -> CorrectionProposal {
        CorrectionProposal(
            original: current,
            replacement: alternate,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            confidence: 1,
            kind: .forced
        )
    }

    private func score(_ word: String, language: LanguageCode) -> Double {
        var result = lexicon.score(word, language: language)
        if spellChecker.isKnown(word, language: language) { result += 3.0 }
        result += scriptCoverage(word, language: language) * 1.8
        result += plausibility(word, language: language)
        result += ngramScore(word, language: language)
        return result
    }

    private func scriptCoverage(_ word: String, language: LanguageCode) -> Double {
        let letters = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return 0 }
        let matching = letters.filter { scalar in
            switch language {
            case .english:
                return (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
            case .russian:
                return (0x0400...0x052F).contains(scalar.value)
            }
        }
        return Double(matching.count) / Double(letters.count)
    }

    private func plausibility(_ word: String, language: LanguageCode) -> Double {
        let value = normalize(word)
        guard value.count >= 2 else { return -1 }
        let vowels = language == .english ? "aeiouy" : "аеёиоуыэюя"
        let vowelCount = value.filter { vowels.contains($0) }.count
        var result = vowelCount > 0 ? 0.8 : -1.0

        let unlikelyClusters = language == .english
            ? ["qj", "wq", "zxq", "jjj", "hhh"]
            : ["ъъ", "ьь", "ййй", "щщщ", "ыыы"]
        if unlikelyClusters.contains(where: value.contains) { result -= 1.5 }
        if value.count > 3 && vowelCount == 0 { result -= 1.2 }
        return result
    }

    private func ngramScore(_ word: String, language: LanguageCode) -> Double {
        let value = normalize(word)
        let commonBigrams: Set<String>
        let commonTrigrams: Set<String>
        switch language {
        case .english:
            commonBigrams = [
                "th", "he", "in", "er", "an", "re", "on", "at", "en", "nd", "ti", "es",
                "or", "te", "of", "ed", "is", "it", "al", "ar", "st", "to", "nt", "ng",
                "se", "ha", "as", "ou", "io", "le", "ve", "co", "me", "de", "hi", "ri"
            ]
            commonTrigrams = [
                "the", "and", "ing", "ion", "tio", "ent", "her", "for", "tha", "nth", "int",
                "ere", "ter", "est", "ers", "ati", "hat", "ate", "all", "ver", "his", "ith"
            ]
        case .russian:
            commonBigrams = [
                "ст", "но", "то", "на", "ен", "ов", "ни", "ра", "во", "ко", "ро", "ер",
                "по", "пр", "ос", "не", "ре", "ал", "ли", "ка", "го", "ть", "та", "от",
                "де", "ит", "ри", "ес", "ва", "те", "ло", "ор", "ле", "ся", "ин", "тр"
            ]
            commonTrigrams = [
                "ого", "его", "что", "ать", "ять", "ить", "ени", "ова", "про", "при", "ств",
                "ост", "ние", "ово", "тся", "ной", "это", "как", "для", "тер", "льн", "ник"
            ]
        }

        let characters = Array(value)
        guard characters.count >= 2 else { return 0 }
        var matches = 0.0
        for index in 0..<(characters.count - 1) {
            if commonBigrams.contains(String(characters[index...index + 1])) { matches += 0.12 }
        }
        if characters.count >= 3 {
            for index in 0..<(characters.count - 2) {
                if commonTrigrams.contains(String(characters[index...index + 2])) { matches += 0.22 }
            }
        }
        return min(matches, 1.4)
    }

    private func normalize(_ word: String) -> String {
        word.lowercased().precomposedStringWithCanonicalMapping
    }

    private func confidenceFrom(margin: Double) -> Double {
        min(0.995, max(0.5, 0.5 + margin / 12.0))
    }
}
