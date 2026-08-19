import Foundation

struct SelectedTextConverter {
    struct Result: Equatable {
        let text: String
        /// D5: при смешанном выделении (слова требуют противоположных направлений) единого
        /// направления не существует. Здесь фиксируется направление ПОСЛЕДНЕГО фактически
        /// преобразованного слова — именно туда попадёт курсор после замены, и именно эта
        /// раскладка нужна пользователю для продолжения ввода (используется в
        /// InputCoordinator.convert() для layoutCatalog.selectLayout(targetID) и для
        /// текста обратной связи). См. CODE_REVIEW_2026-08-19.md, D5.
        let sourceLanguage: LanguageCode
        let targetLanguage: LanguageCode
    }

    /// D5: направление преобразования определяется по каждому слову отдельно, а не по всему
    /// выделению целиком — иначе смешанное выделение вроде "руддщ ghbdtn" (два слова,
    /// требующих противоположных направлений) искажается: часть, уже находящаяся в верной
    /// раскладке, молча портится преобразованием в чужом направлении.
    func convert(
        _ source: String,
        english: KeyboardLayoutSnapshot,
        russian: KeyboardLayoutSnapshot
    ) -> Result? {
        var output = ""
        output.reserveCapacity(source.count)
        var anyChanged = false
        var lastSourceLanguage: LanguageCode?
        var lastTargetLanguage: LanguageCode?

        var index = source.startIndex
        while index < source.endIndex {
            let isWord = Self.isWordCharacter(source[index])
            var end = source.index(after: index)
            while end < source.endIndex, Self.isWordCharacter(source[end]) == isWord {
                end = source.index(after: end)
            }
            let chunk = source[index..<end]

            if isWord {
                let converted = convertWord(chunk, english: english, russian: russian)
                output += converted.text
                if converted.changed {
                    anyChanged = true
                    lastSourceLanguage = converted.sourceLanguage
                    lastTargetLanguage = converted.targetLanguage
                }
            } else {
                // Разделители (пробелы, пунктуация, переводы строк) переносятся в результат
                // побайтово без изменений — они никогда не проходят через карту раскладки.
                output += chunk
            }
            index = end
        }

        guard anyChanged, let sourceLanguage = lastSourceLanguage, let targetLanguage = lastTargetLanguage else {
            return nil
        }
        return Result(text: output, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
    }

    private func convertWord(
        _ word: Substring,
        english: KeyboardLayoutSnapshot,
        russian: KeyboardLayoutSnapshot
    ) -> (text: String, changed: Bool, sourceLanguage: LanguageCode, targetLanguage: LanguageCode) {
        let latinCount = word.unicodeScalars.filter { $0.isLatinLetter }.count
        let cyrillicCount = word.unicodeScalars.filter { $0.isCyrillicLetter }.count
        guard latinCount + cyrillicCount > 0 else {
            // В слове нет ни латинских, ни кириллических букв (например, число) — направление
            // определить нечем, оставляем как есть.
            return (String(word), false, .english, .russian)
        }

        let sourceLanguage: LanguageCode = latinCount >= cyrillicCount ? .english : .russian
        let targetLanguage: LanguageCode = sourceLanguage == .english ? .russian : .english
        let from = sourceLanguage == .english ? english : russian
        let to = sourceLanguage == .english ? russian : english

        var output = ""
        var changed = false
        for character in word {
            if let key = from.physicalKey(for: character), let replacement = to.character(for: key) {
                output.append(replacement)
                if replacement != String(character) { changed = true }
            } else {
                output.append(character)
            }
        }
        return (output, changed, sourceLanguage, targetLanguage)
    }

    /// Синхронизировано с TypingStateMachine.isWordCharacter (см.
    /// wiki/rules/layout-and-input-modeling.md) — то же определение "слова" используется здесь
    /// для сегментации выделения на слова и разделители.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetterOrNumber || character == "'" || character == "’" || character == "-"
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
