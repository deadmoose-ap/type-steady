import AppKit
import ApplicationServices
import Carbon
import Foundation

/// Результат резервной (fallback) замены выделения через Unicode-инъекцию.
/// Отдельно от `Bool`, чтобы вызывающий код мог различить «приложение отказало»
/// и «истёк таймаут ожидания отпускания модификаторов хоткея» — это разные
/// причины отказа и требуют разных сообщений пользователю.
enum SelectionFallbackOutcome {
    case success
    case timedOut
    case failed
}

@MainActor
final class CorrectionCoordinator {
    private let eventTap: InputEventTap
    private let layoutCatalog: LayoutCatalog
    private let synthesizer: EventSynthesizer
    private let logger: DiagnosticLogger
    private let appPolicy = AppPolicy()

    /// Действие инициировано пользователем через хоткей — держать аккорд дольше нормально.
    private static let userInitiatedReleaseTimeout: TimeInterval = 2.0
    /// Автоматическая коррекция на границе слова — пользователь модификаторы не держит.
    private static let automaticReleaseTimeout: TimeInterval = 0.35
    /// Docs/PRIVACY.md: undo доступен максимум восемь секунд — после истечения запись
    /// обнуляется таймером, а не только проверкой возраста в момент использования.
    private static let lastCorrectionLifetime: TimeInterval = 8

    private(set) var lastCorrection: LastCorrection?
    private var lastCorrectionExpiry: DispatchWorkItem?

    /// B1 §A: с переходом на async между шагами транзакции появились точки приостановки —
    /// второй хоткей или второе завершённое слово могут запустить параллельную транзакцию
    /// поверх ещё не завершившейся (раньше apply()/undoLastCorrection()/
    /// replaceSelectionFallback() были синхронны, и это было структурно невозможно).
    /// Флаг — чисто MainActor-состояние (не разделяется с tap-колбэком), поэтому обычного
    /// Bool достаточно: MainActor выполняет только одну задачу одновременно, переключение
    /// между задачами возможно исключительно в точках await, а флаг всегда устанавливается
    /// синхронно сразу после проверки, без await между ними.
    ///
    /// Доступ уровня `internal` (не `private`) — намеренно, только чтобы `@testable`-тест
    /// мог детерминированно воспроизвести состояние «транзакция уже идёт» без гонки таймингов
    /// реального event tap'а. Извне пакета не виден.
    var transactionInProgress = false

    init(
        eventTap: InputEventTap,
        layoutCatalog: LayoutCatalog,
        synthesizer: EventSynthesizer = EventSynthesizer(),
        logger: DiagnosticLogger
    ) {
        self.eventTap = eventTap
        self.layoutCatalog = layoutCatalog
        self.synthesizer = synthesizer
        self.logger = logger
    }

    @discardableResult
    func apply(
        proposal: CorrectionProposal,
        variant: TokenVariant,
        deletionCount: Int,
        sourceLayoutID: String,
        targetLayoutID: String,
        context: AppContext,
        userInitiated: Bool = false
    ) async -> Bool {
        guard preflight(context: context) else {
            logger.record(.correctionFailed, code: 1)
            return false
        }
        guard beginTransaction() else {
            logger.record(.correctionFailed, code: 6)
            return false
        }

        let timeout = userInitiated ? Self.userInitiatedReleaseTimeout : Self.automaticReleaseTimeout
        guard await synthesizer.waitForModifierRelease(timeout: timeout) else {
            logger.record(.correctionFailed, code: 2)
            closeGate()
            endTransaction()
            return false
        }
        // Повторный preflight: за время ожидания (до 2 с при user-initiated) активное
        // приложение или Secure Input могли смениться — проверка перед удалением обязана
        // быть свежей, а не сделанной секунды назад.
        guard preflight(context: context) else {
            logger.record(.correctionFailed, code: 5)
            closeGate()
            endTransaction()
            return false
        }
        eventTap.beginCorrectionGate()
        guard await layoutCatalog.selectLayout(id: targetLayoutID) else {
            logger.record(.correctionFailed, code: 4)
            closeGate()
            endTransaction()
            return false
        }
        try? await Task.sleep(nanoseconds: 12_000_000)

        // B1 §C: между повторным preflight (выше) и этой точкой лежат два неизбежных await —
        // подтверждение переключения раскладки и пауза стабилизации. За это время активное
        // приложение теоретически могло смениться, поэтому прямо перед первым Backspace
        // проверка повторяется в третий раз. Раскладка к этому моменту уже переключена —
        // при отказе она обязана быть возвращена, как и при любом другом отказе после
        // targetSelected.
        guard preflight(context: context) else {
            logger.record(.correctionFailed, code: 7)
            closeGate()
            _ = await layoutCatalog.selectLayout(id: sourceLayoutID)
            endTransaction()
            return false
        }

        do {
            try await synthesizer.sendBackspaces(deletionCount)
            switch proposal.kind {
            case .layout, .forced:
                try await synthesizer.replayPhysicalKeys(variant.keys)
            case .transliteration:
                try await synthesizer.injectUnicode(proposal.replacement)
            }
            try await synthesizer.injectUnicode(variant.boundary)
            setLastCorrection(LastCorrection(
                original: proposal.original,
                replacement: proposal.replacement,
                boundary: variant.boundary,
                sourceLayoutID: sourceLayoutID,
                targetLayoutID: targetLayoutID,
                context: context,
                completedAt: ProcessInfo.processInfo.systemUptime
            ))
            logger.record(.correctionAccepted, value: proposal.replacement.count)
            closeGate()
            endTransaction()
            return true
        } catch {
            logger.record(.correctionFailed, code: 3)
            closeGate()
            _ = await layoutCatalog.selectLayout(id: sourceLayoutID)
            endTransaction()
            return false
        }
    }

    @discardableResult
    func undoLastCorrection() async -> Bool {
        guard let last = lastCorrection,
              ProcessInfo.processInfo.systemUptime - last.completedAt < 8,
              preflight(context: last.context) else { return false }
        guard beginTransaction() else {
            logger.record(.correctionFailed, code: 6)
            return false
        }

        guard await synthesizer.waitForModifierRelease(timeout: Self.userInitiatedReleaseTimeout) else {
            closeGate()
            endTransaction()
            return false
        }
        // Повторный preflight после ожидания — см. комментарий в apply().
        guard preflight(context: last.context) else {
            closeGate()
            endTransaction()
            return false
        }
        eventTap.beginCorrectionGate()
        guard await layoutCatalog.selectLayout(id: last.sourceLayoutID) else {
            closeGate()
            endTransaction()
            return false
        }
        try? await Task.sleep(nanoseconds: 12_000_000)

        // Третий preflight перед первым Backspace — см. комментарий в apply() (B1 §C).
        guard preflight(context: last.context) else {
            closeGate()
            _ = await layoutCatalog.selectLayout(id: last.targetLayoutID)
            endTransaction()
            return false
        }
        do {
            try await synthesizer.sendBackspaces(last.replacement.count + last.boundary.count)
            try await synthesizer.injectUnicode(last.original + last.boundary)
            clearUndo()
            closeGate()
            endTransaction()
            return true
        } catch {
            closeGate()
            _ = await layoutCatalog.selectLayout(id: last.targetLayoutID)
            endTransaction()
            return false
        }
    }

    func replaceSelectionFallback(
        _ replacement: String,
        context: AppContext,
        userInitiated: Bool = false
    ) async -> SelectionFallbackOutcome {
        guard preflight(context: context) else { return .failed }
        guard beginTransaction() else {
            logger.record(.correctionFailed, code: 6)
            return .failed
        }
        let timeout = userInitiated ? Self.userInitiatedReleaseTimeout : Self.automaticReleaseTimeout
        guard await synthesizer.waitForModifierRelease(timeout: timeout) else {
            closeGate()
            endTransaction()
            return .timedOut
        }
        // Повторный preflight после ожидания — см. комментарий в apply(). Здесь отказ — не
        // таймаут, а провал проверки безопасности, поэтому .failed, а не .timedOut.
        guard preflight(context: context) else {
            closeGate()
            endTransaction()
            return .failed
        }
        // Здесь раскладка не переключается, поэтому между этой проверкой и injectUnicode
        // ниже нет ни одного await — beginCorrectionGate() синхронен. Третий preflight
        // (как в apply()/undoLastCorrection()) тут не нужен.
        eventTap.beginCorrectionGate()
        do {
            try await synthesizer.injectUnicode(replacement)
            closeGate()
            endTransaction()
            return .success
        } catch {
            closeGate()
            endTransaction()
            return .failed
        }
    }

    /// Закрывает correction gate (дренаж захваченных событий). Безопасно вызывать даже если
    /// gate не был открыт — finishCorrectionGate() в этом случае просто ничего не находит.
    /// Раньше это жило в `defer`; с async между шагами `defer` с await недопустим, поэтому
    /// вызов повторяется явно на каждом пути выхода после первого preflight.
    private func closeGate() {
        eventTap.finishCorrectionGate { [synthesizer] captured in
            try? synthesizer.replayCapturedEvents(captured)
        }
    }

    private func beginTransaction() -> Bool {
        guard !transactionInProgress else { return false }
        transactionInProgress = true
        return true
    }

    private func endTransaction() {
        transactionInProgress = false
    }

    func clearUndo() {
        lastCorrectionExpiry?.cancel()
        lastCorrectionExpiry = nil
        lastCorrection = nil
    }

    /// Устанавливает новую запись undo и планирует её обнуление через
    /// `lastCorrectionLifetime` — предыдущий таймер отменяется, чтобы данные
    /// прошлой коррекции не пережили дедлайн новой.
    private func setLastCorrection(_ correction: LastCorrection) {
        lastCorrectionExpiry?.cancel()
        lastCorrection = correction
        let work = DispatchWorkItem { [weak self] in
            self?.lastCorrection = nil
        }
        lastCorrectionExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lastCorrectionLifetime, execute: work)
    }

    private func preflight(context: AppContext) -> Bool {
        guard !IsSecureEventInputEnabled(),
              !appPolicy.isHardDenied(bundleIdentifier: context.bundleIdentifier),
              let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier == context.processIdentifier else { return false }
        // F3: без доверенного Accessibility-статуса CGEventPost молча ничего не делает —
        // без этой проверки apply() доходил бы до конца, писал correctionAccepted и создавал
        // запись undo, хотя на экране ничего не происходило (fail closed: без AX коррекция
        // не выполняется, как и раньше по факту, но теперь это видно в логе). Код 8 —
        // следующий свободный после занятых 1..7, отдельный от кодов, которыми вызывающая
        // сторона помечает несовпадение PID и Secure Input, чтобы эта причина отказа не
        // терялась среди них.
        guard AXIsProcessTrusted() else {
            logger.record(.correctionFailed, code: 8)
            return false
        }
        return true
    }
}
