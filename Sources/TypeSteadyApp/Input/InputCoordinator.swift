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
    private let layoutCatalog: LayoutCatalog
    private let detector: DetectionEngine
    private let correction: CorrectionCoordinator
    private let accessibility: AccessibilityTextService
    private let logger: DiagnosticLogger
    private let appPolicy = AppPolicy()
    private let selectedTextConverter = SelectedTextConverter()

    private var state = TypingStateMachine()
    private var modifierOnlyHotkey = ModifierOnlyHotkeyRecognizer()
    private var pendingFlush: DispatchWorkItem?
    private var manualCandidate: ManualCandidate?

    init(
        settings: AppSettings,
        layoutCatalog: LayoutCatalog,
        detector: DetectionEngine,
        correction: CorrectionCoordinator,
        accessibility: AccessibilityTextService,
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
            performHotkeyAction()
            return
        }
        if event.type == .flagsChanged { return }
        if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
            reset()
            return
        }
        guard event.type == .keyDown else { return }
        pendingFlush?.cancel()

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
            process(token, pair: pair)
        }

        if state.hasPendingAmbiguousKey {
            let work = DispatchWorkItem { [weak self] in
                guard let self,
                      let token = self.state.flushAmbiguous(timestamp: ProcessInfo.processInfo.systemUptime),
                      let pair = self.layoutCatalog.activePair(settings: self.settings) else { return }
                self.process(token, pair: pair)
            }
            pendingFlush = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
        }
    }

    func correctLastWord() {
        guard settings.isEnabled else { return }
        if correction.undoLastCorrection() {
            onMessage?("Исправление отменено")
            return
        }
        guard let candidate = manualCandidate,
              ProcessInfo.processInfo.systemUptime - candidate.token.completedAt < 12,
              candidate.token.context == currentContext(),
              let current = candidate.pair.source.render(candidate.variant.keys),
              let alternate = candidate.pair.target.render(candidate.variant.keys) else {
            onMessage?("Нет доступного последнего слова")
            return
        }

        let proposal = detector.forcedProposal(
            current: current,
            alternate: alternate,
            sourceLanguage: candidate.pair.sourceLanguage,
            targetLanguage: candidate.pair.targetLanguage
        )
        if correction.apply(
            proposal: proposal,
            variant: candidate.variant,
            deletionCount: candidate.token.deletionCount,
            sourceLayoutID: candidate.pair.source.descriptor.id,
            targetLayoutID: candidate.pair.target.descriptor.id,
            context: candidate.token.context
        ) {
            state.markCorrectionApplied()
            manualCandidate = nil
            onCorrection?(proposal.sourceLanguage, proposal.targetLanguage)
        }
    }

    func performHotkeyAction() {
        guard settings.isEnabled else { return }
        guard settings.selectionConversion else {
            correctLastWord()
            return
        }

        do {
            let selection = try accessibility.currentSelection()
            convert(selection)
        } catch AccessibilityTextError.noSelection,
                AccessibilityTextError.noFocusedElement,
                AccessibilityTextError.permissionMissing {
            correctLastWord()
        } catch {
            logger.record(.selectionUnavailable)
            onMessage?(error.localizedDescription)
        }
    }

    func convertSelection() {
        guard settings.isEnabled, settings.selectionConversion else { return }
        do {
            let selection = try accessibility.currentSelection()
            convert(selection)
        } catch {
            logger.record(.selectionUnavailable)
            onMessage?(error.localizedDescription)
        }
    }

    func reset() {
        modifierOnlyHotkey.reset()
        pendingFlush?.cancel()
        pendingFlush = nil
        state.invalidate()
        manualCandidate = nil
        correction.clearUndo()
    }

    private func process(_ token: CompletedToken, pair: ActiveLayoutPair) {
        logger.record(.tokenCompleted, value: token.deletionCount)
        manualCandidate = token.variants.first.map { ManualCandidate(token: token, variant: $0, pair: pair) }
        guard settings.automaticCorrection else { return }

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
            return
        }

        if correction.apply(
            proposal: best.1,
            variant: best.0,
            deletionCount: token.deletionCount,
            sourceLayoutID: pair.source.descriptor.id,
            targetLayoutID: pair.target.descriptor.id,
            context: token.context
        ) {
            state.markCorrectionApplied()
            manualCandidate = nil
            onCorrection?(best.1.sourceLanguage, best.1.targetLanguage)
        }
    }

    private func convert(_ selection: AccessibilitySelection) {
        guard !appPolicy.isHardDenied(bundleIdentifier: selection.context.bundleIdentifier),
              let pair = layoutCatalog.selectedPair(settings: settings),
              let conversion = selectedTextConverter.convert(
                selection.text,
                english: pair.english,
                russian: pair.russian
              ) else {
            onMessage?("Выделение не требует преобразования")
            return
        }

        let targetID = conversion.targetLanguage == .english
            ? pair.english.descriptor.id
            : pair.russian.descriptor.id
        guard layoutCatalog.selectLayout(id: targetID) else {
            onMessage?("Целевая раскладка недоступна")
            return
        }

        do {
            let replacedDirectly = try accessibility.replace(selection, with: conversion.text)
            let replaced = replacedDirectly || correction.replaceSelectionFallback(
                conversion.text,
                context: selection.context
            )
            if replaced {
                logger.record(.selectionConverted, value: conversion.text.count)
                onCorrection?(conversion.sourceLanguage, conversion.targetLanguage)
                reset()
            } else {
                logger.record(.selectionUnavailable)
                onMessage?("Это приложение не разрешает заменить выделение")
            }
        } catch {
            logger.record(.selectionUnavailable)
            onMessage?(error.localizedDescription)
        }
    }

    private func physicalKey(from event: InputEventSnapshot) -> PhysicalKey {
        PhysicalKey(
            keyCode: event.keyCode,
            shift: event.flags.contains(.maskShift),
            capsLock: event.flags.contains(.maskAlphaShift)
        )
    }

    private func currentContext() -> AppContext {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        return AppContext(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier ?? "unknown"
        )
    }
}
