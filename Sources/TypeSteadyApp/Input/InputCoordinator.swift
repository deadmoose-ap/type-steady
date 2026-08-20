import AppKit
import Carbon
import CoreGraphics
import Foundation

@MainActor
final class InputCoordinator {
    var onCorrection: ((LanguageCode, LanguageCode) -> Void)?
    var onMessage: ((String) -> Void)?

    private struct ManualCandidate {
        let token: CompletedToken
        let variant: TokenVariant
        let pair: ActiveLayoutPair
    }

    private let settings: AppSettings
    // E1: типы протокольные (LayoutSelecting/SelectionProviding), а не конкретные
    // LayoutCatalog/AccessibilityTextService — иначе convert()/performHotkeyAction()
    // недостижимы для детерминированного теста без реального TIS/AX. Продакшен-поведение
    // не меняется: AppDelegate по-прежнему передаёт настоящие LayoutCatalog/
    // AccessibilityTextService, которые подписаны под протоколы через extension.
    private let layoutCatalog: LayoutSelecting
    private let detector: DetectionEngine
    private let correction: CorrectionCoordinator
    private let accessibility: SelectionProviding
    private let logger: DiagnosticLogger
    private let appPolicy = AppPolicy()
    private let selectedTextConverter = SelectedTextConverter()

    /// Docs/PRIVACY.md: ручная кандидатура живёт максимум 12 секунд — после истечения
    /// поле обнуляется таймером, а не только проверкой возраста в момент использования.
    private static let manualCandidateLifetime: TimeInterval = 12

    // Доступ уровня `internal` (не `private`) — намеренно, только чтобы @testable-тест мог
    // детерминированно проверить содержимое модели, минуя реальный LayoutCatalog/TIS.
    // Извне пакета не виден.
    var state = TypingStateMachine()
    private var modifierOnlyHotkey = ModifierOnlyHotkeyRecognizer()
    private var pendingFlush: DispatchWorkItem?
    /// R5 (пост-ревью B1): process() и флеш неоднозначной пунктуации теперь стартуют как
    /// `Task` из синхронного handle() — между спавном Task и её фактическим стартом есть
    /// оборот main queue, в который может прийти следующий keyDown. Раньше process()
    /// выполнялся синхронно внутри handle(), поэтому state.markCorrectionApplied() успевал
    /// отработать до возврата из handle() — порядок был гарантирован. Теперь это не так:
    /// если следующий keyDown обработается раньше стартовавшей Task, TypingStateMachine
    /// продолжит строить модель поверх уже напечатанного, но ещё неотслеженного символа, а
    /// затем markCorrectionApplied() сотрёт его из модели, хотя на экране он останется.
    /// Флаг выставляется СИНХРОННО в том же обороте handle(), что и state.consume/
    /// flushAmbiguous — до какой-либо точки переключения — и запрещает handle() кормить
    /// TypingStateMachine, пока коррекция не завершится: fail closed, как и остальные
    /// защитные пути этого файла — лучше не предложить коррекцию следующему слову, чем
    /// построить заведомо неверную модель.
    ///
    /// Доступ уровня `internal` — та же причина, что и у `state` выше: тестируемость без
    /// реального event tap/LayoutCatalog. Извне пакета не виден.
    var correctionPending = false
    private var manualCandidate: ManualCandidate? {
        didSet { scheduleManualCandidateExpiry() }
    }
    private var manualCandidateExpiry: DispatchWorkItem?

    // C8: лимит вынесен в общую константу TypeSteadyLimits.maxConvertibleSelectionLength
    // (Core/Models.swift) — тот же лимит теперь также используется в
    // AccessibilityTextService.currentSelection() для ранней проверки ДО чтения текста.

    // B6: раньше currentContext() дёргал NSWorkspace.shared.frontmostApplication на КАЖДЫЙ
    // keyDown. AppDelegate уже наблюдает NSWorkspace.didActivateApplicationNotification и
    // вызывает applicationDidActivate() — кэшируем результат там и читаем кэш здесь.
    // ВАЖНО [граница безопасности]: если кэш пуст (например, до первого уведомления о смене
    // приложения после запуска), currentContext() обязан упасть обратно на прямой вызов
    // NSWorkspace, а не молча вернуть .unknown — иначе на старте приложения проверки
    // isHardDenied/excludedBundleIDSet видели бы неверный контекст. CorrectionCoordinator.preflight()
    // и AccessibilityTextService намеренно НЕ переведены на этот кэш — они сверяют PID
    // непосредственно перед деструктивным действием и должны видеть свежую истину, а не кэш.
    //
    // R6 (пост-ревью спринта 5b): applicationDidActivate() приходит по
    // NSWorkspace.didActivateApplicationNotification, а keyDown-события — по отдельному пути
    // через event tap; порядок доставки между ними не гарантирован. Без ограничения возраста
    // кэш мог пережить реальную смену фронтального приложения на неопределённое время (до
    // следующего уведомления), и hard deny (в т.ч. для менеджеров паролей, [SEC]) проверялся
    // бы по УЖЕ НЕАКТУАЛЬНОМУ bundleIdentifier. Это граница безопасности, а не просто
    // оптимизация: cacheTTL держит окно устаревания коротким и самовосстанавливающимся —
    // currentContext() перечитывает NSWorkspace всякий раз, когда кэшу больше cacheTTL, даже
    // если applicationDidActivate() ещё не вызывался.
    // Доступ уровня `internal` (не `private`) — та же причина, что у `state`/`correctionPending`
    // выше: только чтобы @testable-тест мог детерминированно выставить устаревшее значение и
    // проверить самовосстановление TTL, минуя реальный NSWorkspace. Извне пакета не виден.
    static let cachedContextTTL: TimeInterval = 0.25
    var cachedContext: AppContext?
    var cachedContextTimestamp: TimeInterval = -.infinity

    init(
        settings: AppSettings,
        layoutCatalog: LayoutSelecting,
        detector: DetectionEngine,
        correction: CorrectionCoordinator,
        accessibility: SelectionProviding,
        logger: DiagnosticLogger
    ) {
        self.settings = settings
        self.layoutCatalog = layoutCatalog
        self.detector = detector
        self.correction = correction
        self.accessibility = accessibility
        self.logger = logger
    }

    func handle(_ event: InputEventSnapshot) {
        if modifierOnlyHotkey.consume(event, enabled: settings.manualHotkey == .optionOnly) {
            // B1: performHotkeyAction() теперь async (транзакция коррекции переведена на
            // await, чтобы не блокировать MainActor) — из синхронного колбэка tap'а
            // запускаем её через Task. Task, созданная внутри MainActor-изолированного
            // метода, наследует изоляцию MainActor — [ACT] не нарушается.
            Task { @MainActor [weak self] in
                await self?.performHotkeyAction()
            }
            return
        }
        if event.type == .flagsChanged { return }
        if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
            // Клик мог сменить фокусированный элемент — кэш focusedElementIsSecure() (B3)
            // не должен пережить его дольше своего TTL.
            accessibility.invalidateSecureCache()
            // R6: клик мог сменить и фронтальное приложение (например, клик по окну другого
            // приложения) раньше, чем придёт didActivateApplicationNotification — та же
            // причина, по которой инвалидируется secure-кэш строкой выше.
            invalidateCachedContext()
            reset()
            return
        }
        guard event.type == .keyDown else { return }
        pendingFlush?.cancel()

        if correctionPending {
            // R5: коррекция ещё в полёте (её Task могла ещё не стартовать или уже
            // синтезирует события) — не кормим TypingStateMachine этим keyDown вообще,
            // иначе модель разойдётся с уже напечатанным на экране символом. Просто
            // сбрасываем модель и ждём, пока process() снимет флаг на выходе.
            state.invalidate()
            return
        }

        guard settings.isEnabled, !IsSecureEventInputEnabled() else {
            reset()
            return
        }
        let context = currentContext()
        guard !appPolicy.isHardDenied(bundleIdentifier: context.bundleIdentifier),
              !settings.excludedBundleIDSet.contains(context.bundleIdentifier.lowercased()) else {
            reset()
            return
        }

        let shortcutModifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        let isSwitcherHotkey = settings.manualHotkey.matches(keyCode: event.keyCode, flags: event.flags)
        if correction.lastCorrection != nil && !isSwitcherHotkey {
            correction.clearUndo()
        }
        if !shortcutModifiers.isEmpty {
            if isSwitcherHotkey {
                state.invalidate(preserveLast: true)
            } else {
                reset()
            }
            return
        }

        switch event.keyCode {
        case 51:
            state.backspace(timestamp: event.timestamp)
            return
        case 36, 48, 53, 71, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126:
            reset()
            return
        default:
            break
        }

        guard let pair = layoutCatalog.activePair(settings: settings),
              let currentCharacter = pair.source.character(for: physicalKey(from: event)) else {
            reset()
            return
        }

        if state.activeKeys.isEmpty && accessibility.focusedElementIsSecure() {
            reset()
            return
        }

        let key = physicalKey(from: event)
        let alternateCharacter = pair.target.character(for: key)
        if let token = state.consume(
            key: key,
            currentCharacter: currentCharacter,
            alternateCharacter: alternateCharacter,
            context: context,
            timestamp: event.timestamp
        ) {
            // R5: флаг выставляется синхронно здесь же, в том же обороте handle(), что и
            // state.consume() выше, — до спавна Task и до любой точки переключения.
            correctionPending = true
            Task { @MainActor [weak self] in
                await self?.process(token, pair: pair)
            }
        }

        if state.hasPendingAmbiguousKey {
            let work = DispatchWorkItem { [weak self] in
                guard let self,
                      let token = self.state.flushAmbiguous(timestamp: ProcessInfo.processInfo.systemUptime),
                      let pair = self.layoutCatalog.activePair(settings: self.settings) else { return }
                // R5: та же дисциплина — флаг выставляется синхронно внутри самого work item,
                // до спавна его собственной Task.
                self.correctionPending = true
                Task { @MainActor [weak self] in
                    await self?.process(token, pair: pair)
                }
            }
            pendingFlush = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
        }
    }

    /// A9: `fallbackMessage` переопределяет сообщение "Нет доступного последнего слова" для
    /// случая, когда сюда пришли не из-за отсутствия выделения, а потому что AX-путь уже
    /// отказал с .noSelection/.noFocusedElement — тогда реальная причина в том, что
    /// приложение не публикует kAXSelectedTextAttribute, а не в том, что нет "последнего слова".
    private func correctLastWord(fallbackMessage: String? = nil) async {
        guard settings.isEnabled else { return }
        if await correction.undoLastCorrection() {
            onMessage?("Исправление отменено")
            return
        }
        guard let candidate = manualCandidate,
              ProcessInfo.processInfo.systemUptime - candidate.token.completedAt < 12,
              candidate.token.context == currentContext(),
              let current = candidate.pair.source.render(candidate.variant.keys),
              let alternate = candidate.pair.target.render(candidate.variant.keys) else {
            if let fallbackMessage {
                logger.record(.selectionUnavailable, code: 14)
                onMessage?(fallbackMessage)
            } else {
                onMessage?("Нет доступного последнего слова")
            }
            return
        }

        let proposal = detector.forcedProposal(
            current: current,
            alternate: alternate,
            sourceLanguage: candidate.pair.sourceLanguage,
            targetLanguage: candidate.pair.targetLanguage
        )
        if await correction.apply(
            proposal: proposal,
            variant: candidate.variant,
            deletionCount: candidate.token.deletionCount,
            sourceLayoutID: candidate.pair.source.descriptor.id,
            targetLayoutID: candidate.pair.target.descriptor.id,
            context: candidate.token.context,
            userInitiated: true
        ) {
            state.markCorrectionApplied()
            manualCandidate = nil
            onCorrection?(proposal.sourceLanguage, proposal.targetLanguage)
        }
    }

    func performHotkeyAction() async {
        guard settings.isEnabled else { return }
        guard settings.selectionConversion else {
            await correctLastWord()
            return
        }

        do {
            let selection = try accessibility.currentSelection()
            await convert(selection)
        } catch AccessibilityTextError.permissionMissing {
            // Отдельная ветка: без разрешения Accessibility AX-путь недоступен в принципе,
            // молчаливый уход в correctLastWord() маскировал реальную причину отказа.
            onMessage?("Нет разрешения Accessibility")
        } catch AccessibilityTextError.noSelection,
                AccessibilityTextError.noFocusedElement {
            // A9: AX не отдал выделение — если дальше и correctLastWord() не найдёт кандидата
            // (например, выделение делалось мышью, которая сбрасывает manualCandidate),
            // показать понятную причину, а не общее "Нет доступного последнего слова".
            await correctLastWord(fallbackMessage: "Это приложение не отдаёт выделение через Accessibility")
        } catch AccessibilityTextError.selectionTooLarge {
            // R7 (пост-ревью спринта 5b): C8 добавил раннюю проверку лимита в
            // currentSelection() ДО чтения текста — та же причина отказа, что и запасная
            // проверка в convert() (ветка 1.5, код 13). Код должен совпадать в обоих
            // случаях, иначе одна и та же по смыслу причина отказа различима в логах по
            // тому, публикует ли приложение kAXSelectedTextRangeAttribute — случайная,
            // а не осмысленная развилка.
            logger.record(.selectionUnavailable, code: 13)
            onMessage?(AccessibilityTextError.selectionTooLarge.localizedDescription)
        } catch {
            logger.record(.selectionUnavailable)
            onMessage?(error.localizedDescription)
        }
    }

    /// Смена активного приложения могла сменить фокусированный элемент — кэш
    /// focusedElementIsSecure() (B3) инвалидируется явно, а не по истечении TTL.
    func applicationDidActivate() {
        accessibility.invalidateSecureCache()
        setCachedContext(computeCurrentContext())
        reset()
    }

    func reset() {
        modifierOnlyHotkey.reset()
        pendingFlush?.cancel()
        pendingFlush = nil
        state.invalidate()
        manualCandidate = nil
        correction.clearUndo()
    }

    /// R5: `correctionPending` (выставлен синхронно в `handle()` перед спавном Task, вызвавшей
    /// этот метод) обязан быть сброшен на КАЖДОМ пути выхода — иначе handle() будет
    /// бесконечно fail-closed игнорировать весь дальнейший набор.
    private func process(_ token: CompletedToken, pair: ActiveLayoutPair) async {
        logger.record(.tokenCompleted, value: token.deletionCount)
        manualCandidate = token.variants.first.map { ManualCandidate(token: token, variant: $0, pair: pair) }
        guard settings.automaticCorrection else {
            correctionPending = false
            return
        }

        let evaluated = token.variants.compactMap { variant -> (TokenVariant, CorrectionProposal)? in
            guard let current = pair.source.render(variant.keys),
                  let alternate = pair.target.render(variant.keys),
                  let proposal = detector.proposal(
                    current: current,
                    alternate: alternate,
                    sourceLanguage: pair.sourceLanguage,
                    targetLanguage: pair.targetLanguage,
                    context: token.context,
                    settings: settings
                  ) else { return nil }
            return (variant, proposal)
        }
        guard let best = evaluated.max(by: { $0.1.confidence < $1.1.confidence }) else {
            logger.record(.correctionRejected)
            correctionPending = false
            return
        }

        if await correction.apply(
            proposal: best.1,
            variant: best.0,
            deletionCount: token.deletionCount,
            sourceLayoutID: pair.source.descriptor.id,
            targetLayoutID: pair.target.descriptor.id,
            context: token.context
        ) {
            // markCorrectionApplied() безопасно вызывать даже если activeKeys уже пуст
            // (например, если параллельно отработал reset()/applicationDidActivate() —
            // TypingStateMachine.markCorrectionApplied() просто очищает и так пустые поля).
            state.markCorrectionApplied()
            manualCandidate = nil
            onCorrection?(best.1.sourceLanguage, best.1.targetLanguage)
        }
        correctionPending = false
    }

    private func convert(_ selection: AccessibilitySelection) async {
        // Ветка 1: hard deny или пользовательское исключение приложения.
        // Обе причины действуют всегда, даже для явной команды по хоткею (см. [SEC]).
        guard !appPolicy.isHardDenied(bundleIdentifier: selection.context.bundleIdentifier),
              !settings.excludedBundleIDSet.contains(selection.context.bundleIdentifier.lowercased()) else {
            logger.record(.selectionUnavailable, code: 10)
            onMessage?("Это приложение исключено из преобразования")
            return
        }
        // Ветка 1.5: выделение слишком велико — fallback-путь синтезировал бы десятки тысяч
        // Unicode-событий чанками с Thread.sleep, блокируя main thread на секунды (C5).
        guard selection.text.count <= TypeSteadyLimits.maxConvertibleSelectionLength else {
            logger.record(.selectionUnavailable, code: 13)
            onMessage?("Выделение слишком большое для преобразования")
            return
        }
        // Ветка 2: для активной раскладки не настроена пара English/Russian.
        guard let pair = layoutCatalog.selectedPair(settings: settings) else {
            logger.record(.selectionUnavailable, code: 11)
            onMessage?("Пара раскладок для преобразования не настроена")
            return
        }
        // Ветка 3: в выделении реально нет символов, которые можно преобразовать.
        guard let conversion = selectedTextConverter.convert(
            selection.text,
            english: pair.english,
            russian: pair.russian
        ) else {
            logger.record(.selectionUnavailable, code: 12)
            onMessage?("В выделении нет символов для преобразования")
            return
        }

        let targetID = conversion.targetLanguage == .english
            ? pair.english.descriptor.id
            : pair.russian.descriptor.id
        let originalLayoutID = layoutCatalog.currentLayoutID()
        guard await layoutCatalog.selectLayout(id: targetID) else {
            onMessage?("Целевая раскладка недоступна")
            return
        }

        // Симметрично CorrectionCoordinator.apply(): при неудаче вернуть исходную раскладку.
        // Раньше это было в `defer`; с async между шагами `defer` с await недопустим, поэтому
        // откат раскладки сделан явным присваиванием ниже, после do-catch, на любом исходе.
        var replaced = false

        do {
            if try accessibility.replace(selection, with: conversion.text) {
                replaced = true
            } else {
                switch await correction.replaceSelectionFallback(
                    conversion.text,
                    context: selection.context,
                    userInitiated: true
                ) {
                case .success:
                    replaced = true
                case .timedOut:
                    onMessage?("Отпустите клавиши хоткея")
                case .failed:
                    onMessage?("Это приложение не разрешает заменить выделение")
                }
            }
            if replaced {
                logger.record(.selectionConverted, value: conversion.text.count)
                onCorrection?(conversion.sourceLanguage, conversion.targetLanguage)
                reset()
            } else {
                logger.record(.selectionUnavailable)
            }
        } catch {
            logger.record(.selectionUnavailable)
            onMessage?(error.localizedDescription)
        }

        if !replaced, let originalLayoutID {
            _ = await layoutCatalog.selectLayout(id: originalLayoutID)
        }
    }

    /// Отменяет предыдущий таймер и, если появилась новая кандидатура, планирует её
    /// обнуление через `manualCandidateLifetime` — симметрично `lastCorrection` в
    /// `CorrectionCoordinator`.
    private func scheduleManualCandidateExpiry() {
        manualCandidateExpiry?.cancel()
        manualCandidateExpiry = nil
        guard manualCandidate != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.manualCandidate = nil
        }
        manualCandidateExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.manualCandidateLifetime, execute: work)
    }

    private func physicalKey(from event: InputEventSnapshot) -> PhysicalKey {
        PhysicalKey(
            keyCode: event.keyCode,
            shift: event.flags.contains(.maskShift),
            capsLock: event.flags.contains(.maskAlphaShift)
        )
    }

    // internal — см. комментарий у cachedContext выше.
    func currentContext() -> AppContext {
        // B6/R6: кэш заполняется в applicationDidActivate(), но используется, только пока он
        // не старше cachedContextTTL — см. комментарий у cachedContextTTL выше. Если кэш пуст
        // ИЛИ устарел, fail-open на прямой опрос NSWorkspace и обновляем кэш заново — не
        // ослаблять проверки устаревшим/пустым значением.
        let now = ProcessInfo.processInfo.systemUptime
        if let cachedContext, now - cachedContextTimestamp < Self.cachedContextTTL {
            return cachedContext
        }
        let fresh = computeCurrentContext()
        setCachedContext(fresh, at: now)
        return fresh
    }

    private func computeCurrentContext() -> AppContext {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        return AppContext(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier ?? "unknown"
        )
    }

    private func setCachedContext(_ context: AppContext, at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        cachedContext = context
        cachedContextTimestamp = timestamp
    }

    /// R6: клик (см. handle()) обязан инвалидировать кэш, а не просто дать ему истечь по TTL —
    /// клик мог сменить фронтальное приложение немедленно, и до истечения TTL окно
    /// устаревания было бы шире необходимого.
    private func invalidateCachedContext() {
        cachedContext = nil
        cachedContextTimestamp = -.infinity
    }
}
