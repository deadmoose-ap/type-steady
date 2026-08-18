import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var permissions: PermissionManager!
    private var launchAtLogin: LaunchAtLoginController!
    private var layouts: LayoutCatalog!
    private var logger: DiagnosticLogger!
    private var eventTap: InputEventTap!
    private var correction: CorrectionCoordinator!
    private var inputCoordinator: InputCoordinator!
    private var hotkeys: GlobalHotkeyManager!
    private var feedback: FeedbackPresenter!
    private var statusBar: StatusBarController!
    private var settingsWindow: SettingsWindowController!
    private var observers: [NSObjectProtocol] = []
    private var lastHotkeyChoice: HotkeyChoice?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = AppSettings()
        permissions = PermissionManager()
        launchAtLogin = LaunchAtLoginController()
        layouts = LayoutCatalog()
        logger = DiagnosticLogger()
        eventTap = InputEventTap()
        feedback = FeedbackPresenter()

        logger.isEnabled = { UserDefaults.standard.object(forKey: "diagnostics") as? Bool ?? false }
        layouts.refresh(settings: settings)

        correction = CorrectionCoordinator(eventTap: eventTap, layoutCatalog: layouts, logger: logger)
        inputCoordinator = InputCoordinator(
            settings: settings,
            layoutCatalog: layouts,
            detector: DetectionEngine(),
            correction: correction,
            accessibility: AccessibilityTextService(),
            logger: logger
        )
        inputCoordinator.onCorrection = { [weak self] source, target in
            guard let self else { return }
            self.feedback.show(
                "\(source.displayName) → \(target.displayName)",
                sound: self.settings.soundFeedback,
                visual: self.settings.visualFeedback
            )
        }
        inputCoordinator.onMessage = { [weak self] message in
            guard let self else { return }
            self.feedback.show(message, sound: false, visual: self.settings.visualFeedback)
        }

        eventTap.onEvent = { [weak self] event in self?.inputCoordinator.handle(event) }
        eventTap.onTapDisabled = { [weak self] in
            self?.logger.record(.eventTapDisabled)
        }

        hotkeys = GlobalHotkeyManager()
        hotkeys.onPerformTextAction = { [weak self] in self?.inputCoordinator.performHotkeyAction() }

        statusBar = StatusBarController(settings: settings)
        configureStatusBarCallbacks()

        let settingsView = SettingsView(
            settings: settings,
            layouts: layouts,
            permissions: permissions,
            launchAtLogin: launchAtLogin,
            refreshLayouts: { [weak self] in self?.refreshLayouts() },
            restartMonitor: { [weak self] in self?.restartMonitor() }
        )
        settingsWindow = SettingsWindowController(rootView: settingsView)

        installObservers()
        applySettings()

        if !permissions.accessibilityGranted || !permissions.inputMonitoringGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.settingsWindow.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap?.stop()
        hotkeys?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func configureStatusBarCallbacks() {
        statusBar.onToggleEnabled = { [weak self] in
            guard let self else { return }
            self.settings.isEnabled.toggle()
        }
        statusBar.onToggleAutomatic = { [weak self] in
            guard let self else { return }
            self.settings.automaticCorrection.toggle()
        }
        statusBar.onToggleTransliteration = { [weak self] in
            guard let self else { return }
            self.settings.transliteration.toggle()
        }
        statusBar.onCorrectLastWord = { [weak self] in self?.inputCoordinator.correctLastWord() }
        statusBar.onConvertSelection = { [weak self] in self?.inputCoordinator.convertSelection() }
        statusBar.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
    }

    private func installObservers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .typeSteadySettingsChanged,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.inputCoordinator.reset()
                self?.permissions.refresh()
            }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.Carbon.TISNotifyEnabledKeyboardInputSourcesChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLayouts() }
        })
    }

    private func applySettings() {
        statusBar.updateAppearance()
        if lastHotkeyChoice != settings.manualHotkey {
            hotkeys.start(choice: settings.manualHotkey)
            lastHotkeyChoice = settings.manualHotkey
        }
        if settings.isEnabled {
            if !eventTap.start() {
                logger.record(.eventTapStopped, code: 1)
            } else {
                logger.record(.eventTapStarted)
            }
        } else {
            eventTap.stop()
            inputCoordinator.reset()
            logger.record(.eventTapStopped)
        }
    }

    private func restartMonitor() {
        eventTap.stop()
        permissions.refresh()
        if settings.isEnabled, !eventTap.start() {
            feedback.show("Разрешение Input Monitoring ещё не действует", sound: false, visual: true)
        }
    }

    private func refreshLayouts() {
        inputCoordinator.reset()
        layouts.refresh(settings: settings)
        logger.record(.layoutRefresh, value: layouts.descriptors.count)
    }
}
