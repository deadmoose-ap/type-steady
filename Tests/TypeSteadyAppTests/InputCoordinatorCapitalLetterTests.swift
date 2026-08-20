import Carbon
import CoreGraphics
import Foundation
import Testing
@testable import TypeSteadyApp

// G1: до фикса InputCoordinator.handle() включал .maskShift в shortcutModifiers — обычный
// набор заглавной буквы (Shift+буква) ошибочно считался «сочетанием клавиш» и сбрасывал
// TypingStateMachine ДО того, как заглавная буква попадала в модель. Пользователь сообщил об
// этом через правило «Никогда не исправлять» («Леша» → «Лtif»), но дефект шире: ЛОМАЕТСЯ ЛЮБОЕ
// слово с заглавной буквы, потому что первая буква всегда терялась. Тесты ниже воспроизводят
// это на уровне InputCoordinator.handle(), используя протокольные швы LayoutSelecting/
// SelectionProviding из E1 (как в InputCoordinatorConversionTests) — так раскладка
// детерминирована и не зависит от того, какие TIS-источники установлены на машине, где
// запускаются тесты.

@MainActor
private final class NoOpSelectionProvider: SelectionProviding {
    func currentSelection() throws -> AccessibilitySelection { throw AccessibilityTextError.noSelection }
    func replace(_ selection: AccessibilitySelection, with replacement: String) throws -> Bool { false }
    func focusedElementIsSecure() -> Bool { false }
    func invalidateSecureCache() {}
}

@MainActor
private final class FixedLayoutSelector: LayoutSelecting {
    var activePairStub: ActiveLayoutPair?

    func selectedPair(settings: AppSettings) -> (english: KeyboardLayoutSnapshot, russian: KeyboardLayoutSnapshot)? {
        nil
    }

    func activePair(settings: AppSettings) -> ActiveLayoutPair? { activePairStub }

    func currentLayoutID() -> String? { nil }

    func selectLayout(id: String) async -> Bool { false }
}

@MainActor
struct InputCoordinatorCapitalLetterTests {
    private static let testContext = AppContext(processIdentifier: 1, bundleIdentifier: "test.editor")

    private func makeSettings() -> AppSettings {
        let suite = "TypeSteady.CapitalLetterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    private func makeCoordinator(settings: AppSettings, layouts: FixedLayoutSelector, detector: DetectionEngine) -> InputCoordinator {
        let tap = InputEventTap()
        let realLayouts = LayoutCatalog() // как в InputCoordinatorConversionTests — только для CorrectionCoordinator
        let logger = DiagnosticLogger()
        let correction = CorrectionCoordinator(eventTap: tap, layoutCatalog: realLayouts, logger: logger)
        let coordinator = InputCoordinator(
            settings: settings,
            layoutCatalog: layouts,
            detector: detector,
            correction: correction,
            accessibility: NoOpSelectionProvider(),
            logger: logger
        )
        // Фиксированный, заведомо не hard-denied контекст — без реального NSWorkspace.
        coordinator.cachedContext = Self.testContext
        coordinator.cachedContextTimestamp = ProcessInfo.processInfo.systemUptime
        return coordinator
    }

    // MARK: - «Леша»: активна русская раскладка, физические клавиши k(Shift), t, i, f

    /// Физическая позиция клавиши K на клавиатуре: в русской раскладке (активной) с Shift даёт
    /// «Л», в английской (целевой) — «K». Аналогично t/i/f → е/ш/а (рус.) и t/i/f (англ. —
    /// тождественно, как и в реальной QWERTY/ЙЦУКЕН раскладке).
    private func leshaLayoutPair() -> ActiveLayoutPair {
        let k = PhysicalKey(keyCode: 40, shift: true, capsLock: false)
        let t = PhysicalKey(keyCode: 17, shift: false, capsLock: false)
        let i = PhysicalKey(keyCode: 34, shift: false, capsLock: false)
        let f = PhysicalKey(keyCode: 3, shift: false, capsLock: false)
        let space = PhysicalKey(keyCode: UInt16(kVK_Space), shift: false, capsLock: false)

        let russian = KeyboardLayoutSnapshot.testLayout(
            id: "ru.test", name: "Russian", language: .russian,
            characters: [k: "Л", t: "е", i: "ш", f: "а", space: " "]
        )
        let english = KeyboardLayoutSnapshot.testLayout(
            id: "en.test", name: "English", language: .english,
            characters: [k: "K", t: "t", i: "i", f: "f", space: " "]
        )
        return ActiveLayoutPair(source: russian, target: english)
    }

    private func leshaEvents() -> [InputEventSnapshot] {
        [
            InputEventSnapshot(type: .keyDown, keyCode: 40, flags: [.maskShift], isRepeat: false, timestamp: 1),
            InputEventSnapshot(type: .keyDown, keyCode: 17, flags: [], isRepeat: false, timestamp: 2),
            InputEventSnapshot(type: .keyDown, keyCode: 34, flags: [], isRepeat: false, timestamp: 3),
            InputEventSnapshot(type: .keyDown, keyCode: 3, flags: [], isRepeat: false, timestamp: 4),
            InputEventSnapshot(type: .keyDown, keyCode: UInt16(kVK_Space), flags: [], isRepeat: false, timestamp: 5)
        ]
    }

    // 1. Слово с заглавной буквы целиком попадает в модель.
    @Test func capitalLetterWordIsCapturedWholeIntoModel() {
        let settings = makeSettings()
        // Отключаем автокоррекцию — этот тест проверяет ИСКЛЮЧИТЕЛЬНО то, что модель
        // (TypingStateMachine) получила все 4 физические клавиши, а не решение детектора.
        settings.automaticCorrection = false

        let layouts = FixedLayoutSelector()
        let pair = leshaLayoutPair()
        layouts.activePairStub = pair
        let coordinator = makeCoordinator(settings: settings, layouts: layouts, detector: DetectionEngine())

        for event in leshaEvents() { coordinator.handle(event) }

        let keys = coordinator.state.lastCompleted?.variants.first?.keys ?? []
        // До фикса здесь было 3 ключа («еша») — Shift+K сбрасывал состояние ДО того, как
        // попасть в activeKeys, потому что .maskShift считался «сочетанием клавиш».
        #expect(keys.count == 4)
        #expect(pair.source.render(keys) == "Леша")
    }

    // 2. Слово с заглавной, входящее в «Никогда не исправлять», НЕ исправляется — правило
    // срабатывает по ПОЛНОМУ, а не обрезанному слову.
    @Test func capitalLetterWordInNeverCorrectListIsNotCorrected() {
        let layouts = FixedLayoutSelector()
        let pair = leshaLayoutPair()
        layouts.activePairStub = pair

        // Лексикон подобран так, чтобы "Ktif" реально выглядел как правдоподобное английское
        // слово (иначе тест ничего не доказывает про guard — proposal мог бы отсутствовать
        // просто из-за низкого скора, а не из-за правила).
        let lexicon = LocalLexicon(common: [.english: ["ktif"], .russian: []])
        let detector = DetectionEngine(lexicon: lexicon, spellChecker: NullSpellChecker())

        let settingsWithRule = makeSettings()
        settingsWithRule.automaticCorrection = false // detector вызывается напрямую ниже
        settingsWithRule.neverConvert = "Леша"
        let coordinator = makeCoordinator(settings: settingsWithRule, layouts: layouts, detector: detector)

        for event in leshaEvents() { coordinator.handle(event) }

        let keys = coordinator.state.lastCompleted?.variants.first?.keys ?? []
        let current = pair.source.render(keys) ?? ""
        let alternate = pair.target.render(keys) ?? ""
        #expect(current == "Леша")
        #expect(alternate == "Ktif")

        let proposalWithRule = detector.proposal(
            current: current, alternate: alternate,
            sourceLanguage: pair.sourceLanguage, targetLanguage: pair.targetLanguage,
            context: Self.testContext, settings: settingsWithRule
        )
        #expect(proposalWithRule == nil)

        // Контроль: те же строки, тот же лексикон, но БЕЗ правила — детектор реально
        // предложил бы коррекцию. Доказывает, что отсутствие proposal выше — заслуга guard'а
        // (проверяющего ПОЛНОЕ, регистронезависимое слово «Леша»), а не случайность скоринга.
        let settingsWithoutRule = makeSettings()
        let proposalWithoutRule = detector.proposal(
            current: current, alternate: alternate,
            sourceLanguage: pair.sourceLanguage, targetLanguage: pair.targetLanguage,
            context: Self.testContext, settings: settingsWithoutRule
        )
        #expect(proposalWithoutRule != nil)
    }

    // 3. Слово с заглавной, НЕ входящее в исключения, исправляется корректно и целиком —
    // включая первую (заглавную) букву в замене.
    @Test func capitalLetterWordNotExcludedIsCorrectedWhole() {
        // Активна английская раскладка (пользователь забыл переключиться) — физические клавиши
        // Shift+g,h,b,d,t,n на английской дают «Ghbdtn» (бессмыслица), на русской — «Привет».
        let capitalG = PhysicalKey(keyCode: 5, shift: true, capsLock: false)
        let h = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        let b = PhysicalKey(keyCode: 11, shift: false, capsLock: false)
        let d = PhysicalKey(keyCode: 2, shift: false, capsLock: false)
        let t = PhysicalKey(keyCode: 17, shift: false, capsLock: false)
        let n = PhysicalKey(keyCode: 45, shift: false, capsLock: false)
        let space = PhysicalKey(keyCode: UInt16(kVK_Space), shift: false, capsLock: false)

        let english = KeyboardLayoutSnapshot.testLayout(
            id: "en.test", name: "English", language: .english,
            characters: [capitalG: "G", h: "h", b: "b", d: "d", t: "t", n: "n", space: " "]
        )
        let russian = KeyboardLayoutSnapshot.testLayout(
            id: "ru.test", name: "Russian", language: .russian,
            characters: [capitalG: "П", h: "р", b: "и", d: "в", t: "е", n: "т", space: " "]
        )
        let pair = ActiveLayoutPair(source: english, target: russian)

        let layouts = FixedLayoutSelector()
        layouts.activePairStub = pair

        // "привет" — как и в DetectionEngineTests.detectsWrongLayout — реальный лексиконный
        // кейс, не подогнанный специально под этот тест.
        let lexicon = LocalLexicon(common: [.english: [], .russian: ["привет"]])
        let detector = DetectionEngine(lexicon: lexicon, spellChecker: NullSpellChecker())

        let settings = makeSettings()
        settings.automaticCorrection = false
        let coordinator = makeCoordinator(settings: settings, layouts: layouts, detector: detector)

        let events: [InputEventSnapshot] = [
            InputEventSnapshot(type: .keyDown, keyCode: 5, flags: [.maskShift], isRepeat: false, timestamp: 1),
            InputEventSnapshot(type: .keyDown, keyCode: 4, flags: [], isRepeat: false, timestamp: 2),
            InputEventSnapshot(type: .keyDown, keyCode: 11, flags: [], isRepeat: false, timestamp: 3),
            InputEventSnapshot(type: .keyDown, keyCode: 2, flags: [], isRepeat: false, timestamp: 4),
            InputEventSnapshot(type: .keyDown, keyCode: 17, flags: [], isRepeat: false, timestamp: 5),
            InputEventSnapshot(type: .keyDown, keyCode: 45, flags: [], isRepeat: false, timestamp: 6),
            InputEventSnapshot(type: .keyDown, keyCode: UInt16(kVK_Space), flags: [], isRepeat: false, timestamp: 7)
        ]
        for event in events { coordinator.handle(event) }

        let keys = coordinator.state.lastCompleted?.variants.first?.keys ?? []
        #expect(keys.count == 6)
        let current = pair.source.render(keys) ?? ""
        let alternate = pair.target.render(keys) ?? ""
        #expect(current == "Ghbdtn")
        #expect(alternate == "Привет")

        let proposal = detector.proposal(
            current: current, alternate: alternate,
            sourceLanguage: pair.sourceLanguage, targetLanguage: pair.targetLanguage,
            context: Self.testContext, settings: settings
        )
        // Целиком, вместе с заглавной буквой — не "ривет".
        #expect(proposal?.replacement == "Привет")
    }

    // 4. ⌃⇧Space по-прежнему распознаётся как хоткей и не ломает (не сбрасывает целиком)
    // состояние — Shift остаётся частью флагов хоткея (полное сравнение в
    // HotkeyChoice.matches), даже когда его исключили из shortcutModifiers.
    @Test func controlShiftSpaceHotkeyStillRecognizedAfterShiftFix() {
        let settings = makeSettings()
        settings.manualHotkey = .controlShiftSpace
        let layouts = FixedLayoutSelector()
        let coordinator = makeCoordinator(settings: settings, layouts: layouts, detector: DetectionEngine())

        // Готовим lastCompleted, чтобы отличить preserveLast:true (ветка хоткея) от
        // обычного reset() (стирает lastCompleted).
        let letter = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        _ = coordinator.state.consume(
            key: letter, currentCharacter: "a", alternateCharacter: "ф",
            context: Self.testContext, timestamp: 1
        )
        let completed = coordinator.state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ", alternateCharacter: " ",
            context: Self.testContext, timestamp: 2
        )
        #expect(completed != nil)
        #expect(coordinator.state.lastCompleted != nil)

        coordinator.handle(InputEventSnapshot(
            type: .keyDown,
            keyCode: UInt16(kVK_Space),
            flags: [.maskControl, .maskShift],
            isRepeat: false,
            timestamp: 3
        ))

        // shortcutModifiers теперь [.maskControl] (Shift исключён), но всё ещё НЕ пуст —
        // ветка isSwitcherHotkey срабатывает, как и раньше. HotkeyChoice.matches сравнивает
        // ПОЛНЫЙ набор флагов события (включая Shift), поэтому совпадение не потеряно.
        #expect(coordinator.state.lastCompleted != nil)
        #expect(coordinator.state.activeKeys.isEmpty)
    }

    // Доп. проверка: Shift+стрелка (выделение текста) по-прежнему сбрасывает состояние —
    // стрелки отсекаются в switch по keyCode НИЖЕ проверки shortcutModifiers, и теперь без
    // Shift в наборе туда попадают напрямую (shortcutModifiers пуст), а не через ветку хоткея.
    @Test func shiftArrowStillResetsState() {
        let settings = makeSettings()
        let layouts = FixedLayoutSelector()
        let coordinator = makeCoordinator(settings: settings, layouts: layouts, detector: DetectionEngine())

        let letter = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        _ = coordinator.state.consume(
            key: letter, currentCharacter: "a", alternateCharacter: "ф",
            context: Self.testContext, timestamp: 1
        )
        #expect(coordinator.state.activeKeys == [letter])

        // 123 = стрелка влево (см. switch в InputCoordinator.handle()).
        coordinator.handle(InputEventSnapshot(
            type: .keyDown, keyCode: 123, flags: [.maskShift], isRepeat: false, timestamp: 2
        ))

        #expect(coordinator.state.activeKeys.isEmpty)
        #expect(coordinator.state.lastCompleted == nil)
    }

    // R10 (пост-ревью Opus 5): Shift+Delete НАМЕРЕННО сбрасывает состояние, а не вызывает
    // state.backspace(). Поведение Shift+Delete зависит от приложения/поля (в части из них —
    // delete-to-end-of-line или удаление слова целиком, а не одного символа), и по одному
    // событию клавиатуры это доказать нельзя. Предположение «минус один физический ключ» было
    // бы небезопасным: если реально удалено больше символов, чем один, модель разойдётся с
    // экраном, и коррекция впоследствии сотрёт текст ПЕРЕД словом неверным deletionCount —
    // тот же fail-closed принцип, что и у границы «. », которую обычный Backspace не
    // переоткрывает (wiki/rules/layout-and-input-modeling.md).
    @Test func shiftDeleteResetsStateInsteadOfAssumingSingleCharacterDeletion() {
        let settings = makeSettings()
        let layouts = FixedLayoutSelector()
        let coordinator = makeCoordinator(settings: settings, layouts: layouts, detector: DetectionEngine())

        let first = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        let second = PhysicalKey(keyCode: 5, shift: false, capsLock: false)
        _ = coordinator.state.consume(
            key: first, currentCharacter: "a", alternateCharacter: "ф",
            context: Self.testContext, timestamp: 1
        )
        _ = coordinator.state.consume(
            key: second, currentCharacter: "b", alternateCharacter: "и",
            context: Self.testContext, timestamp: 2
        )
        #expect(coordinator.state.activeKeys == [first, second])

        coordinator.handle(InputEventSnapshot(
            type: .keyDown, keyCode: 51, flags: [.maskShift], isRepeat: false, timestamp: 3
        ))

        // reset() стёр обе клавиши целиком — модель не строит предположений о длине удаления.
        #expect(coordinator.state.activeKeys.isEmpty)
        #expect(coordinator.state.lastCompleted == nil)
    }

    // Контроль к тесту выше: обычный Backspace (без Shift) обязан продолжать работать как
    // раньше — удалять один физический ключ из activeKeys, а после одиночного простого
    // разделителя переоткрывать только что завершённое слово (backspaceReopensRecentWord в
    // TypingStateMachineTests покрывает это на уровне модели; здесь — тем же путём, что и
    // Shift+Delete выше, через InputCoordinator.handle(), чтобы явно показать разницу).
    @Test func plainBackspaceStillRemovesOneKeyAndReopensCompletedWord() {
        let settings = makeSettings()
        let layouts = FixedLayoutSelector()
        let coordinator = makeCoordinator(settings: settings, layouts: layouts, detector: DetectionEngine())

        let first = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        let second = PhysicalKey(keyCode: 5, shift: false, capsLock: false)
        _ = coordinator.state.consume(
            key: first, currentCharacter: "a", alternateCharacter: "ф",
            context: Self.testContext, timestamp: 1
        )
        _ = coordinator.state.consume(
            key: second, currentCharacter: "b", alternateCharacter: "и",
            context: Self.testContext, timestamp: 2
        )
        #expect(coordinator.state.activeKeys == [first, second])

        coordinator.handle(InputEventSnapshot(
            type: .keyDown, keyCode: 51, flags: [], isRepeat: false, timestamp: 3
        ))

        // Обычный Backspace — только один физический ключ, не reset().
        #expect(coordinator.state.activeKeys == [first])

        // Переоткрытие только что завершённого слова после простого разделителя.
        _ = coordinator.state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ", alternateCharacter: " ",
            context: Self.testContext, timestamp: 4
        )
        #expect(coordinator.state.activeKeys.isEmpty)
        #expect(coordinator.state.lastCompleted != nil)

        coordinator.handle(InputEventSnapshot(
            type: .keyDown, keyCode: 51, flags: [], isRepeat: false, timestamp: 5
        ))
        #expect(coordinator.state.activeKeys == [first])
        #expect(coordinator.state.lastCompleted == nil)
    }
}
