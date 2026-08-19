import Testing
@testable import TypeSteadyApp

struct SelectedTextConverterTests {
    private func layouts() -> (KeyboardLayoutSnapshot, KeyboardLayoutSnapshot) {
        let keys = (0..<6).map { PhysicalKey(keyCode: UInt16($0), shift: false, capsLock: false) }
        let english = KeyboardLayoutSnapshot.testLayout(
            id: "en",
            name: "English",
            language: .english,
            characters: Dictionary(uniqueKeysWithValues: zip(keys, ["g", "h", "b", "d", "t", "n"]))
        )
        let russian = KeyboardLayoutSnapshot.testLayout(
            id: "ru",
            name: "Russian",
            language: .russian,
            characters: Dictionary(uniqueKeysWithValues: zip(keys, ["п", "р", "и", "в", "е", "т"]))
        )
        return (english, russian)
    }

    @Test func convertsByPhysicalKeys() {
        let (english, russian) = layouts()

        let result = SelectedTextConverter().convert("ghbdtn", english: english, russian: russian)
        #expect(result?.text == "привет")
        #expect(result?.sourceLanguage == .english)
        #expect(result?.targetLanguage == .russian)
    }

    @Test func convertsCyrillicBackToLatin() {
        let (english, russian) = layouts()
        let result = SelectedTextConverter().convert("привет", english: english, russian: russian)
        #expect(result?.text == "ghbdtn")
        #expect(result?.sourceLanguage == .russian)
        #expect(result?.targetLanguage == .english)
    }

    @Test func preservesUnsupportedCharacters() {
        let (english, russian) = layouts()
        let result = SelectedTextConverter().convert("gh!", english: english, russian: russian)
        #expect(result?.text == "пр!")
    }

    @Test func rejectsTextWithoutLettersOrConvertibleCharacters() {
        let (english, russian) = layouts()
        #expect(SelectedTextConverter().convert("123!?", english: english, russian: russian) == nil)
        #expect(SelectedTextConverter().convert("xyz", english: english, russian: russian) == nil)
    }

    // MARK: - D5: направление по каждому слову отдельно

    /// Расширенная раскладка, покрывающая оба слова из главного кейса пользователя:
    /// "hello" (h,e,l,o) и "привет"/"ghbdtn" (g,h,b,d,t,n) — буква 'h' общая для обоих слов
    /// и мапится согласованно в обеих группах ('h' <-> 'р').
    private func mixedLayouts() -> (KeyboardLayoutSnapshot, KeyboardLayoutSnapshot) {
        let keys = (0..<9).map { PhysicalKey(keyCode: UInt16($0), shift: false, capsLock: false) }
        let english = KeyboardLayoutSnapshot.testLayout(
            id: "en",
            name: "English",
            language: .english,
            characters: Dictionary(
                uniqueKeysWithValues: zip(keys, ["h", "e", "l", "o", "g", "b", "d", "t", "n"])
            )
        )
        let russian = KeyboardLayoutSnapshot.testLayout(
            id: "ru",
            name: "Russian",
            language: .russian,
            characters: Dictionary(
                uniqueKeysWithValues: zip(keys, ["р", "у", "д", "щ", "п", "и", "в", "е", "т"])
            )
        )
        return (english, russian)
    }

    @Test func mixedSelectionConvertsEachWordByItsOwnDirection() {
        let (english, russian) = mixedLayouts()
        // Главный кейс пользователя: "руддщ" (hello, набранное в русской раскладке) +
        // "ghbdtn" (привет, набранное в английской) в одном выделении.
        let result = SelectedTextConverter().convert("руддщ ghbdtn", english: english, russian: russian)
        #expect(result?.text == "hello привет")
        // Последнее фактически преобразованное слово — "ghbdtn" (EN -> RU).
        #expect(result?.sourceLanguage == .english)
        #expect(result?.targetLanguage == .russian)
    }

    @Test func mixedSelectionReversedOrderTracksLastConvertedWord() {
        let (english, russian) = mixedLayouts()
        let result = SelectedTextConverter().convert("ghbdtn руддщ", english: english, russian: russian)
        #expect(result?.text == "привет hello")
        // Последнее слово — "руддщ" (RU -> EN).
        #expect(result?.sourceLanguage == .russian)
        #expect(result?.targetLanguage == .english)
    }

    @Test func homogeneousEnglishToRussianSelectionStillWorks() {
        let (english, russian) = mixedLayouts()
        let result = SelectedTextConverter().convert("ghbdtn ghbdtn", english: english, russian: russian)
        #expect(result?.text == "привет привет")
        #expect(result?.sourceLanguage == .english)
        #expect(result?.targetLanguage == .russian)
    }

    @Test func homogeneousRussianToEnglishSelectionStillWorks() {
        let (english, russian) = mixedLayouts()
        let result = SelectedTextConverter().convert("руддщ руддщ", english: english, russian: russian)
        #expect(result?.text == "hello hello")
        #expect(result?.sourceLanguage == .russian)
        #expect(result?.targetLanguage == .english)
    }

    @Test func punctuationBetweenWordsIsPreservedExactly() {
        let (english, russian) = mixedLayouts()
        let result = SelectedTextConverter().convert("ghbdtn, ghbdtn!", english: english, russian: russian)
        #expect(result?.text == "привет, привет!")
    }

    @Test func digitsInsideAWordAreLeftUnconvertedButWordBoundaryIsRespected() {
        let (english, russian) = mixedLayouts()
        // "abc123" — псевдослово: 'b' конвертируется (есть в карте), 'a'/'c'/цифры остаются
        // как есть (нет соответствия в карте), но граница слова перед "ghbdtn" сохраняется.
        let result = SelectedTextConverter().convert("abc123 ghbdtn", english: english, russian: russian)
        #expect(result?.text == "aиc123 привет")
    }

    @Test func wordWithoutLettersIsLeftUnchanged() {
        let (english, russian) = mixedLayouts()
        #expect(SelectedTextConverter().convert("12345", english: english, russian: russian) == nil)
    }

    @Test func selectionWithNothingToConvertReturnsNil() {
        let (english, russian) = mixedLayouts()
        #expect(SelectedTextConverter().convert("!!! ...", english: english, russian: russian) == nil)
    }

    @Test func newlineSeparatorIsPreserved() {
        let (english, russian) = mixedLayouts()
        let result = SelectedTextConverter().convert("ghbdtn\nghbdtn", english: english, russian: russian)
        #expect(result?.text == "привет\nпривет")
    }
}
