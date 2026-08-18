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
        do {
            for permission in PrivacyPermission.allCases {
                try reset(permission, bundleIdentifier: bundleIdentifier)
            }
            refresh()
            repairMessage = "Старые записи удалены. Подтвердите Accessibility, затем Input Monitoring."
            requestAccessibility()
        } catch {
            repairMessage = "Не удалось сбросить записи автоматически. Удалите TypeSteady кнопкой «−» в обоих разделах macOS."
            openAccessibilitySettings()
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

    private func reset(_ permission: PrivacyPermission, bundleIdentifier: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", permission.rawValue, bundleIdentifier]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableRuntimeMismatch)
        }
    }
}
