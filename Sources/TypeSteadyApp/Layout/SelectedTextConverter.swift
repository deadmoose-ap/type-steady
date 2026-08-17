import Foundation

struct SelectedTextConverter {
    struct Result: Equatable {
        let text: String
        let sourceLanguage: LanguageCode
        let targetLanguage: LanguageCode
    }

    func convert(
        _ source: String,
        english: KeyboardLayoutSnapshot,
        russian: KeyboardLayoutSnapshot
    ) -> Result? {
        let latinCount = source.unicodeScalars.filter { $0.isLatinLetter }.count
        let cyrillicCount = source.unicodeScalars.filter { $0.isCyrillicLetter }.count
        guard latinCount + cyrillicCount > 0 else { return nil }

        let sourceLanguage: LanguageCode = latinCount >= cyrillicCount ? .english : .russian
        let targetLanguage: LanguageCode = sourceLanguage == .english ? .russian : .english
        let from = sourceLanguage == .english ? english : russian
        let to = sourceLanguage == .english ? russian : english
        var output = ""
        var convertedCount = 0

        for character in source {
            if let key = from.physicalKey(for: character), let replacement = to.character(for: key) {
                output.append(replacement)
                if replacement != String(character) { convertedCount += 1 }
            } else {
                output.append(character)
            }
        }
        guard convertedCount > 0 else { return nil }
        return Result(text: output, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
    }
}

private extension Unicode.Scalar {
    var isLatinLetter: Bool {
        (0x0041...0x005A).contains(value) || (0x0061...0x007A).contains(value)
    }

    var isCyrillicLetter: Bool {
        (0x0400...0x052F).contains(value)
    }
}
