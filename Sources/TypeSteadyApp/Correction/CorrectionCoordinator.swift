import AppKit
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

    private(set) var lastCorrection: LastCorrection?

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
    ) -> Bool {
        guard preflight(context: context) else {
            logger.record(.correctionFailed, code: 1)
            return false
        }

        var succeeded = false
        var targetSelected = false
        defer {
            eventTap.finishCorrectionGate { [synthesizer] captured in
                try? synthesizer.replayCapturedEvents(captured)
            }
            if targetSelected && !succeeded { _ = layoutCatalog.selectLayout(id: sourceLayoutID) }
        }

        let timeout = userInitiated ? Self.userInitiatedReleaseTimeout : Self.automaticReleaseTimeout
        guard synthesizer.waitForModifierRelease(timeout: timeout) else {
            logger.record(.correctionFailed, code: 2)
            return false
        }
        // Повторный preflight: за время ожидания (до 2 с при user-initiated) активное
        // приложение или Secure Input могли смениться — проверка перед удалением обязана
        // быть свежей, а не сделанной секунды назад.
        guard preflight(context: context) else {
            logger.record(.correctionFailed, code: 5)
            return false
        }
        eventTap.beginCorrectionGate()
        guard layoutCatalog.selectLayout(id: targetLayoutID) else {
            logger.record(.correctionFailed, code: 4)
            return false
        }
        targetSelected = true
        Thread.sleep(forTimeInterval: 0.012)

        do {
            try synthesizer.sendBackspaces(deletionCount)
            switch proposal.kind {
            case .layout, .forced:
                try synthesizer.replayPhysicalKeys(variant.keys)
            case .transliteration:
                try synthesizer.injectUnicode(proposal.replacement)
            }
            try synthesizer.injectUnicode(variant.boundary)
            succeeded = true
            lastCorrection = LastCorrection(
                original: proposal.original,
                replacement: proposal.replacement,
                boundary: variant.boundary,
                sourceLayoutID: sourceLayoutID,
                targetLayoutID: targetLayoutID,
                context: context,
                completedAt: ProcessInfo.processInfo.systemUptime
            )
            logger.record(.correctionAccepted, value: proposal.replacement.count)
            return true
        } catch {
            logger.record(.correctionFailed, code: 3)
            return false
        }
    }

    @discardableResult
    func undoLastCorrection() -> Bool {
        guard let last = lastCorrection,
              ProcessInfo.processInfo.systemUptime - last.completedAt < 8,
              preflight(context: last.context) else { return false }

        var succeeded = false
        var sourceSelected = false
        defer {
            eventTap.finishCorrectionGate { [synthesizer] captured in
                try? synthesizer.replayCapturedEvents(captured)
            }
            if sourceSelected && !succeeded { _ = layoutCatalog.selectLayout(id: last.targetLayoutID) }
        }

        guard synthesizer.waitForModifierRelease(timeout: Self.userInitiatedReleaseTimeout) else { return false }
        // Повторный preflight после ожидания — см. комментарий в apply().
        guard preflight(context: last.context) else { return false }
        eventTap.beginCorrectionGate()
        guard layoutCatalog.selectLayout(id: last.sourceLayoutID) else { return false }
        sourceSelected = true
        Thread.sleep(forTimeInterval: 0.012)
        do {
            try synthesizer.sendBackspaces(last.replacement.count + last.boundary.count)
            try synthesizer.injectUnicode(last.original + last.boundary)
            lastCorrection = nil
            succeeded = true
            return true
        } catch {
            return false
        }
    }

    func replaceSelectionFallback(
        _ replacement: String,
        context: AppContext,
        userInitiated: Bool = false
    ) -> SelectionFallbackOutcome {
        guard preflight(context: context) else { return .failed }
        defer {
            eventTap.finishCorrectionGate { [synthesizer] captured in
                try? synthesizer.replayCapturedEvents(captured)
            }
        }
        let timeout = userInitiated ? Self.userInitiatedReleaseTimeout : Self.automaticReleaseTimeout
        guard synthesizer.waitForModifierRelease(timeout: timeout) else { return .timedOut }
        // Повторный preflight после ожидания — см. комментарий в apply(). Здесь отказ — не
        // таймаут, а провал проверки безопасности, поэтому .failed, а не .timedOut.
        guard preflight(context: context) else { return .failed }
        eventTap.beginCorrectionGate()
        do {
            try synthesizer.injectUnicode(replacement)
            return .success
        } catch {
            return .failed
        }
    }

    func clearUndo() {
        lastCorrection = nil
    }

    private func preflight(context: AppContext) -> Bool {
        guard !IsSecureEventInputEnabled(),
              !appPolicy.isHardDenied(bundleIdentifier: context.bundleIdentifier),
              let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier == context.processIdentifier else { return false }
        return true
    }
}
