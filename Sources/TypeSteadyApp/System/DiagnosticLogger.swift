import Foundation
import OSLog

enum DiagnosticEvent: String {
    case eventTapStarted
    case eventTapStopped
    case eventTapDisabled
    case tokenCompleted
    case correctionAccepted
    case correctionRejected
    case correctionFailed
    case selectionConverted
    case selectionUnavailable
    case layoutRefresh
    case permissionState
    /// Correction gate был закрыт принудительно watchdog'ом или дедлайном итераций,
    /// а не штатным опустошением очереди захваченных событий (см. code review B2).
    case correctionGateForcedClosed
}

final class DiagnosticLogger {
    private let logger = Logger(subsystem: "local.typesteady.app", category: "diagnostics")
    var isEnabled: () -> Bool = { false }

    func record(_ event: DiagnosticEvent, value: Int = 0, code: Int = 0) {
        guard isEnabled() else { return }
        logger.info("event=\(event.rawValue, privacy: .public) value=\(value, privacy: .public) code=\(code, privacy: .public)")
    }
}
