import ApplicationServices
import AppKit
import Combine
import CoreGraphics

enum PrivacyPermission: String, CaseIterable {
    case accessibility = "Accessibility"
    case inputMonitoring = "ListenEvent"

    var settingsAnchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .inputMonitoring: return "Privacy_ListenEvent"
        }
    }

    var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(settingsAnchor)")!
    }
}

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var repairMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAfterRequest(.accessibility)
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        refreshAfterRequest(.inputMonitoring)
    }

    func openAccessibilitySettings() {
        openPrivacyPane(.accessibility)
    }

    func openInputMonitoringSettings() {
        openPrivacyPane(.inputMonitoring)
    }

    func repairStaleRecords() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? AppPolicy.typeSteadyBundleIdentifier
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Последовательный сброс: сперва Accessibility, затем ListenEvent — область
                // не расширяется, только собственный bundle ID (см. [SEC]).
                for permission in PrivacyPermission.allCases {
                    try await self.reset(permission, bundleIdentifier: bundleIdentifier)
                }
                self.refresh()
                self.repairMessage = "Старые записи удалены. Подтвердите Accessibility, затем Input Monitoring."
                self.requestAccessibility()
            } catch {
                self.repairMessage = "Не удалось сбросить записи автоматически. Удалите TypeSteady кнопкой «−» в обоих разделах macOS."
                self.openAccessibilitySettings()
            }
        }
    }

    private func refreshAfterRequest(_ permission: PrivacyPermission) {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            self.refresh()
            let granted = permission == .accessibility
                ? self.accessibilityGranted
                : self.inputMonitoringGranted
            if !granted {
                self.openPrivacyPane(permission)
            }
        }
    }

    private func openPrivacyPane(_ permission: PrivacyPermission) {
        if !NSWorkspace.shared.open(permission.settingsURL),
           let fallback = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            NSWorkspace.shared.open(fallback)
        }
    }

    /// Асинхронное ожидание завершения `tccutil` через `terminationHandler` — раньше
    /// `waitUntilExit()` блокировал главный поток на @MainActor (C4).
    private func reset(_ permission: PrivacyPermission, bundleIdentifier: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", permission.rawValue, bundleIdentifier]
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            throw CocoaError(.executableRuntimeMismatch)
        }
    }
}
