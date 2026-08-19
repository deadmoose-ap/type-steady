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
    private var tapRecoveryWorkItem: DispatchWorkItem?
    private var lastAutomaticTapRecoveryAt: TimeInterval = -.infinity

    /// B10: отдельный от `handleTapDisabled`/`tapRecoveryWorkItem` механизм. Он реагирует
    /// только на неудачу CGEvent.tapCreate ВНУТРИ applySettings()/start() — то есть на старте,
    /// когда TCC для Input Monitoring ещё не «ожил» для процесса, хотя CGPreflightListenEventAccess
    /// уже мог вернуть true. [REN]: этот retry никогда не запускается из onTapDisabled и не
    /// реанимирует tap, отключённый системой — это делает исключительно handleTapDisabled
    /// со своим независимым rate-limit'ом.
    private var startRetryWorkItem: DispatchWorkItem?
    private var startRetryAttempt = 0
    private static let startRetryDelays: [TimeInterval] = [0.5, 1.5, 3.0]

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
        eventTap.onTapDisabled = { [weak self] reason in self?.handleTapDisabled(reason) }
        eventTap.onGateForceClosed = { [weak self] dropped in
            self?.logger.record(.correctionGateForcedClosed, value: dropped)
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
        tapRecoveryWorkItem?.cancel()
        startRetryWorkItem?.cancel()
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
                self?.inputCoordinator.applicationDidActivate()
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
            // Любая новая попытка старта (в т.ч. повторный applySettings) отменяет
            // предыдущую цепочку retry — не наслаиваем несколько параллельных серий.
            cancelStartRetry()
            if !eventTap.start() {
                logger.record(.eventTapStopped, code: 1)
                // B10: неудача старта не должна быть беззвучной — раньше об этом не
                // сообщалось никак, и симптом «заработало после смены хоткея» на самом
                // деле был просто повторной попыткой eventTap.start() из applySettings().
                feedback.show("Разрешение Input Monitoring ещё не действует", sound: false, visual: true)
                scheduleStartRetry()
            } else {
                logger.record(.eventTapStarted)
            }
        } else {
            cancelStartRetry()
            eventTap.stop()
            inputCoordinator.reset()
            logger.record(.eventTapStopped)
        }
    }

    /// B10: до 3 повторных попыток eventTap.start() с задержками 0.5/1.5/3 с. Каждая
    /// попытка выполняется только если settings.isEnabled к этому моменту всё ещё true.
    /// Полностью независим от handleTapDisabled — не трогает isGating/tapRecoveryWorkItem
    /// и никогда не вызывается из onTapDisabled, поэтому не может участвовать в цикле
    /// восстановления отключённого системой tap'а ([REN]).
    private func scheduleStartRetry() {
        guard startRetryAttempt < Self.startRetryDelays.count else {
            feedback.show(
                "Не удалось запустить мониторинг — нажмите «Проверить снова»",
                sound: false,
                visual: true
            )
            startRetryAttempt = 0
            return
        }
        let delay = Self.startRetryDelays[startRetryAttempt]
        startRetryAttempt += 1
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.startRetryWorkItem = nil
            guard self.settings.isEnabled else { return }
            if self.eventTap.start() {
                self.logger.record(.eventTapStarted)
                self.startRetryAttempt = 0
            } else {
                self.logger.record(.eventTapStopped, code: 1)
                self.scheduleStartRetry()
            }
        }
        startRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelStartRetry() {
        startRetryWorkItem?.cancel()
        startRetryWorkItem = nil
        startRetryAttempt = 0
    }

    private func restartMonitor() {
        tapRecoveryWorkItem?.cancel()
        tapRecoveryWorkItem = nil
        cancelStartRetry()
        eventTap.stop()
        permissions.refresh()
        if settings.isEnabled, !eventTap.start() {
            feedback.show("Разрешение Input Monitoring ещё не действует", sound: false, visual: true)
            scheduleStartRetry()
        }
    }

    private func handleTapDisabled(_ reason: InputEventTapDisableReason) {
        logger.record(.eventTapDisabled)
        // Гигиена, не смешивание механизмов: если по какой-то случайности параллельно
        // тикает retry неудачного старта (B10), не даём ему пересечься с восстановлением
        // отключённого системой tap'а — они физически не пересекаются по сценарию
        // (start-retry работает только пока start() не вернул true), но останавливаем явно.
        cancelStartRetry()
        eventTap.stop()
        inputCoordinator.reset()
        permissions.refresh()

        guard reason == .timeout else {
            feedback.show(
                "Мониторинг остановлен после изменения разрешений",
                sound: false,
                visual: settings.visualFeedback
            )
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard settings.isEnabled,
              permissions.accessibilityGranted,
              permissions.inputMonitoringGranted,
              now - lastAutomaticTapRecoveryAt >= 15 else {
            feedback.show(
                "Мониторинг остановлен — нажмите «Проверить снова»",
                sound: false,
                visual: settings.visualFeedback
            )
            return
        }

        lastAutomaticTapRecoveryAt = now
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.permissions.refresh()
            guard self.settings.isEnabled,
                  self.permissions.accessibilityGranted,
                  self.permissions.inputMonitoringGranted,
                  self.eventTap.start() else {
                self.feedback.show(
                    "Мониторинг остановлен — проверьте разрешения",
                    sound: false,
                    visual: self.settings.visualFeedback
                )
                return
            }
            self.logger.record(.eventTapStarted)
        }
        tapRecoveryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    private func refreshLayouts() {
        inputCoordinator.reset()
        layouts.refresh(settings: settings)
        logger.record(.layoutRefresh, value: layouts.descriptors.count)
    }
}
