import ApplicationServices
import AppKit
import Testing
@testable import TypeSteadyApp

// E1: InputCoordinator.convert()/performHotkeyAction() до этого спринта не были покрыты
// интеграционно — тестировался только чистый SelectedTextConverter. Именно поэтому баги A1
// (пункты меню) и A2/A3 (хоткей) дошли до сборки. Протокольные швы SelectionProviding
// (над AccessibilityTextService) и LayoutSelecting (над LayoutCatalog) позволяют подставить
// детерминированные фейки вместо реального AX/TIS.
//
// AccessibilitySelection.element — настоящий AXUIElement. Продакшен-тип решено не трогать
// (см. CODE_REVIEW E1, п.4) — фейковый элемент создаётся через
// AXUIElementCreateApplication(getpid()), как и рекомендовано: валидный AXUIElement,
// указывающий на собственный процесс теста, не требующий разрешения Accessibility для
// самого факта создания структуры (методы AX на нём в тестах не вызываются — заменой
// занимается FakeSelectionProvider, а не реальный AXUIElementSetAttributeValue).

@MainActor
private final class FakeSelectionProvider: SelectionProviding {
    enum Stub {
        case value(AccessibilitySelection)
        case error(AccessibilityTextError)
    }

    var currentSelectionStub: Stub = .error(.noSelection)
    var replaceResult: Result<Bool, Error> = .success(true)

    private(set) var currentSelectionCallCount = 0
    private(set) var replaceCallCount = 0
    private(set) var invalidateSecureCacheCallCount = 0
    var focusedElementIsSecureStub = false

    func currentSelection() throws -> AccessibilitySelection {
        currentSelectionCallCount += 1
        switch currentSelectionStub {
        case .value(let selection): return selection
        case .error(let error): throw error
        }
    }

    func replace(_ selection: AccessibilitySelection, with replacement: String) throws -> Bool {
        replaceCallCount += 1
        return try replaceResult.get()
    }

    func focusedElementIsSecure() -> Bool { focusedElementIsSecureStub }

    func invalidateSecureCache() { invalidateSecureCacheCallCount += 1 }
}

@MainActor
private final class FakeLayoutSelector: LayoutSelecting {
    var selectedPairStub: (english: KeyboardLayoutSnapshot, russian: KeyboardLayoutSnapshot)?
    var activePairStub: ActiveLayoutPair?
    var currentLayoutIDStub: String? = "en"
    var selectLayoutResult = true

    /// Порядок вызовов selectLayout(id:) — тест на откат (D-A4) проверяет, что после
    /// отказа замены раскладка переключается обратно на исходную, а не только "куда-то".
    private(set) var selectLayoutCalls: [String] = []

    func selectedPair(settings: AppSettings) -> (english: KeyboardLayoutSnapshot, russian: KeyboardLayoutSnapshot)? {
        selectedPairStub
    }

    func activePair(settings: AppSettings) -> ActiveLayoutPair? { activePairStub }

    func currentLayoutID() -> String? { currentLayoutIDStub }

    func selectLayout(id: String) async -> Bool {
        selectLayoutCalls.append(id)
        return selectLayoutResult
    }
}

@MainActor
struct InputCoordinatorConversionTests {
    private func makeSettings() -> AppSettings {
        let name = "TypeSteady.ConversionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.selectionConversion = true
        return settings
    }

    /// Фейковый, но валидный AXUIElement — см. комментарий над файлом.
    private func fakeElement() -> AXUIElement {
        AXUIElementCreateApplication(getpid())
    }

    private func makeLayouts() -> (english: KeyboardLayoutSnapshot, russian: KeyboardLayoutSnapshot) {
        let keys = (0..<6).map { PhysicalKey(keyCode: UInt16($0), shift: false, capsLock: false) }
        let english = KeyboardLayoutSnapshot.testLayout(
            id: "en.test", name: "English", language: .english,
            characters: Dictionary(uniqueKeysWithValues: zip(keys, ["g", "h", "b", "d", "t", "n"]))
        )
        let russian = KeyboardLayoutSnapshot.testLayout(
            id: "ru.test", name: "Russian", language: .russian,
            characters: Dictionary(uniqueKeysWithValues: zip(keys, ["п", "р", "и", "в", "е", "т"]))
        )
        return (english, russian)
    }

    /// Контекст с ЗАВЕДОМО несуществующим pid — preflight() в CorrectionCoordinator
    /// (`frontmost.processIdentifier == context.processIdentifier`) на нём гарантированно
    /// проваливается, поэтому replaceSelectionFallback() детерминированно и БЕЗОПАСНО
    /// возвращает .failed до какой-либо синтезированной клавиатуры — реальные события в
    /// систему не отправляются. Тем же путём проверяется откат раскладки (D-A4) и переход
    /// AX-неудачи в fallback (A2).
    private func unreachableContext() -> AppContext {
        AppContext(processIdentifier: -1, bundleIdentifier: "com.example.target")
    }

    private func makeCoordinator(
        settings: AppSettings,
        accessibility: FakeSelectionProvider,
        layouts: FakeLayoutSelector
    ) -> InputCoordinator {
        let tap = InputEventTap()
        let realLayouts = LayoutCatalog()
        let logger = DiagnosticLogger()
        let correction = CorrectionCoordinator(eventTap: tap, layoutCatalog: realLayouts, logger: logger)
        return InputCoordinator(
            settings: settings,
            layoutCatalog: layouts,
            detector: DetectionEngine(),
            correction: correction,
            accessibility: accessibility,
            logger: logger
        )
    }

    // MARK: - Успешная замена через AX

    @Test func successfulAXReplaceSwitchesLayoutAndReportsSuccess() async {
        let settings = makeSettings()
        let accessibility = FakeSelectionProvider()
        let layouts = FakeLayoutSelector()
        let (english, russian) = makeLayouts()
        layouts.selectedPairStub = (english, russian)
        layouts.currentLayoutIDStub = "en.test"

        let selection = AccessibilitySelection(
            element: fakeElement(),
            text: "ghbdtn",
            context: AppContext(processIdentifier: 1, bundleIdentifier: "com.example.target")
        )
        accessibility.currentSelectionStub = .value(selection)
        accessibility.replaceResult = .success(true)

        let coordinator = makeCoordinator(settings: settings, accessibility: accessibility, layouts: layouts)

        var reportedSource: LanguageCode?
        var reportedTarget: LanguageCode?
        coordinator.onCorrection = { source, target in
            reportedSource = source
            reportedTarget = target
        }
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        await coordinator.performHotkeyAction()

        #expect(accessibility.replaceCallCount == 1)
        // Раскладка переключена на целевую (русскую) — единственный вызов selectLayout.
        #expect(layouts.selectLayoutCalls == ["ru.test"])
        #expect(reportedSource == .english)
        #expect(reportedTarget == .russian)
        #expect(messages.isEmpty) // успех сигнализируется через onCorrection, не onMessage.
    }

    // MARK: - AX-замена отказала → fallback → откат раскладки

    @Test func failedAXReplaceFallsBackAndRollsBackLayoutOnFailure() async {
        let settings = makeSettings()
        let accessibility = FakeSelectionProvider()
        let layouts = FakeLayoutSelector()
        let (english, russian) = makeLayouts()
        layouts.selectedPairStub = (english, russian)
        layouts.currentLayoutIDStub = "en.test"

        let selection = AccessibilitySelection(
            element: fakeElement(),
            text: "ghbdtn",
            context: unreachableContext()
        )
        accessibility.currentSelectionStub = .value(selection)
        accessibility.replaceResult = .success(false) // AX отказала (не бросила ошибку, просто false)

        let coordinator = makeCoordinator(settings: settings, accessibility: accessibility, layouts: layouts)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }
        var corrected = false
        coordinator.onCorrection = { _, _ in corrected = true }

        await coordinator.performHotkeyAction()

        #expect(accessibility.replaceCallCount == 1)
        // Ушли в fallback (CorrectionCoordinator.replaceSelectionFallback), который на
        // недостижимом pid детерминированно возвращает .failed — сообщение об отказе.
        #expect(messages == ["Это приложение не разрешает заменить выделение"])
        #expect(!corrected)
        // D-A4: раскладка переключена на целевую, а затем ОТКАЧЕНА обратно на исходную —
        // без этого регрессия A4 (раскладка молча остаётся на целевой при отказе замены).
        #expect(layouts.selectLayoutCalls == ["ru.test", "en.test"])
    }

    // MARK: - Приложение в hard deny

    @Test func hardDeniedApplicationRefusesWithCode10() async {
        let settings = makeSettings()
        let accessibility = FakeSelectionProvider()
        let layouts = FakeLayoutSelector()
        let (english, russian) = makeLayouts()
        layouts.selectedPairStub = (english, russian)

        let selection = AccessibilitySelection(
            element: fakeElement(),
            text: "ghbdtn",
            // [SEC]: собственный bundle ID TypeSteady — hard deny должен сработать даже
            // для явной команды по хоткею.
            context: AppContext(processIdentifier: 1, bundleIdentifier: AppPolicy.typeSteadyBundleIdentifier)
        )
        accessibility.currentSelectionStub = .value(selection)

        let coordinator = makeCoordinator(settings: settings, accessibility: accessibility, layouts: layouts)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        await coordinator.performHotkeyAction()

        #expect(messages == ["Это приложение исключено из преобразования"])
        #expect(accessibility.replaceCallCount == 0)
        #expect(layouts.selectLayoutCalls.isEmpty)
    }

    // MARK: - Приложение в пользовательских исключениях (регрессия A5)

    @Test func userExcludedApplicationRefusesWithCode10() async {
        let settings = makeSettings()
        settings.excludedBundleIDs = "com.example.excluded"
        let accessibility = FakeSelectionProvider()
        let layouts = FakeLayoutSelector()
        let (english, russian) = makeLayouts()
        layouts.selectedPairStub = (english, russian)

        let selection = AccessibilitySelection(
            element: fakeElement(),
            text: "ghbdtn",
            context: AppContext(processIdentifier: 1, bundleIdentifier: "com.example.excluded")
        )
        accessibility.currentSelectionStub = .value(selection)

        let coordinator = makeCoordinator(settings: settings, accessibility: accessibility, layouts: layouts)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        await coordinator.performHotkeyAction()

        #expect(messages == ["Это приложение исключено из преобразования"])
        #expect(accessibility.replaceCallCount == 0)
    }

    // MARK: - Пара раскладок не настроена

    @Test func missingLayoutPairRefusesWithCode11() async {
        let settings = makeSettings()
        let accessibility = FakeSelectionProvider()
        let layouts = FakeLayoutSelector()
        layouts.selectedPairStub = nil

        let selection = AccessibilitySelection(
            element: fakeElement(),
            text: "ghbdtn",
            context: AppContext(processIdentifier: 1, bundleIdentifier: "com.example.target")
        )
        accessibility.currentSelectionStub = .value(selection)

        let coordinator = makeCoordinator(settings: settings, accessibility: accessibility, layouts: layouts)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        await coordinator.performHotkeyAction()

        #expect(messages == ["Пара раскладок для преобразования не настроена"])
        #expect(accessibility.replaceCallCount == 0)
    }

    // MARK: - Нечего преобразовывать

    @Test func nothingConvertibleRefusesWithCode12() async {
        let settings = makeSettings()
        let accessibility = FakeSelectionProvider()
        let layouts = FakeLayoutSelector()
        let (english, russian) = makeLayouts()
        layouts.selectedPairStub = (english, russian)

        // "123!?" не содержит символов, которые есть в тестовой раскладке — SelectedTextConverter
        // вернёт nil (см. SelectedTextConverterTests.rejectsTextWithoutLettersOrConvertibleCharacters).
        let selection = AccessibilitySelection(
            element: fakeElement(),
            text: "123!?",
            context: AppContext(processIdentifier: 1, bundleIdentifier: "com.example.target")
        )
        accessibility.currentSelectionStub = .value(selection)

        let coordinator = makeCoordinator(settings: settings, accessibility: accessibility, layouts: layouts)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        await coordinator.performHotkeyAction()

        #expect(messages == ["В выделении нет символов для преобразования"])
        #expect(accessibility.replaceCallCount == 0)
    }

    // MARK: - Выделение больше лимита

    @Test func oversizedSelectionRefusesWithCode13() async {
        let settings = makeSettings()
        let accessibility = FakeSelectionProvider()
        let layouts = FakeLayoutSelector()
        let (english, russian) = makeLayouts()
        layouts.selectedPairStub = (english, russian)

        let selection = AccessibilitySelection(
            element: fakeElement(),
            text: String(repeating: "g", count: TypeSteadyLimits.maxConvertibleSelectionLength + 1),
            context: AppContext(processIdentifier: 1, bundleIdentifier: "com.example.target")
        )
        accessibility.currentSelectionStub = .value(selection)

        let coordinator = makeCoordinator(settings: settings, accessibility: accessibility, layouts: layouts)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        await coordinator.performHotkeyAction()

        #expect(messages == ["Выделение слишком большое для преобразования"])
        #expect(accessibility.replaceCallCount == 0)
    }

    // MARK: - permissionMissing не должен уходить в correctLastWord() (регрессия A8)

    @Test func permissionMissingShowsMessageWithoutFallingBackToLastWord() async {
        let settings = makeSettings()
        let accessibility = FakeSelectionProvider()
        let layouts = FakeLayoutSelector()
        accessibility.currentSelectionStub = .error(.permissionMissing)

        let coordinator = makeCoordinator(settings: settings, accessibility: accessibility, layouts: layouts)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        await coordinator.performHotkeyAction()

        // Ровно одно сообщение про разрешение — если бы код (регрессия A8) молча ушёл в
        // correctLastWord(), сообщение было бы другим ("Нет доступного последнего слова").
        #expect(messages == ["Нет разрешения Accessibility"])
    }

    // MARK: - noSelection уходит в correctLastWord() с fallbackMessage (регрессия A9)

    @Test func noSelectionFallsBackToLastWordWithFallbackMessage() async {
        let settings = makeSettings()
        let accessibility = FakeSelectionProvider()
        let layouts = FakeLayoutSelector()
        accessibility.currentSelectionStub = .error(.noSelection)

        let coordinator = makeCoordinator(settings: settings, accessibility: accessibility, layouts: layouts)
        var messages: [String] = []
        coordinator.onMessage = { messages.append($0) }

        await coordinator.performHotkeyAction()

        // correctLastWord() без manualCandidate и без undo-истории выдаёт fallbackMessage,
        // переданный из ветки .noSelection — не общее "Нет доступного последнего слова".
        #expect(messages == ["Это приложение не отдаёт выделение через Accessibility"])
    }
}
