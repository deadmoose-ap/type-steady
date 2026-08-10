import AppKit
import Carbon
import Foundation

@MainActor
final class CorrectionCoordinator {
    private let eventTap: InputEventTap
    private let layoutCatalog: LayoutCatalog
    private let synthesizer: EventSynthesizer
    private let logger: DiagnosticLogger
    private let appPolicy = AppPolicy()

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
        context: AppContext
    ) -> Bool {
        guard preflight(context: context) else {
            logger.record(.correctionFailed, code: 1)
            return false
        }

        eventTap.beginCorrectionGate()
        var succeeded = false
        var targetSelected = false
        defer {
            eventTap.finishCorrectionGate { [synthesizer] captured in
                try? synthesizer.replayCapturedEvents(captured)
            }
            if targetSelected && !succeeded { _ = layoutCatalog.selectLayout(id: sourceLayoutID) }
        }

        guard synthesizer.waitForModifierRelease() else {
            logger.record(.correctionFailed, code: 2)
            return false
        }
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

        eventTap.beginCorrectionGate()
        var succeeded = false
        var sourceSelected = false
        defer {
            eventTap.finishCorrectionGate { [synthesizer] captured in
                try? synthesizer.replayCapturedEvents(captured)
            }
            if sourceSelected && !succeeded { _ = layoutCatalog.selectLayout(id: last.targetLayoutID) }
        }

        guard synthesizer.waitForModifierRelease() else { return false }
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

    func replaceSelectionFallback(_ replacement: String, context: AppContext) -> Bool {
        guard preflight(context: context) else { return false }
        eventTap.beginCorrectionGate()
        defer {
            eventTap.finishCorrectionGate { [synthesizer] captured in
                try? synthesizer.replayCapturedEvents(captured)
            }
        }
        guard synthesizer.waitForModifierRelease() else { return false }
        do {
            try synthesizer.injectUnicode(replacement)
            return true
        } catch {
            return false
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
