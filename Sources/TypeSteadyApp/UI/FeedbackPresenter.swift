import AppKit

@MainActor
final class FeedbackPresenter {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    /// F2: короткая длительность — как было раньше, для «English → Русский» этого достаточно
    /// (значение по умолчанию, чтобы существующие вызовы без явного duration не изменили поведение).
    /// `nonisolated`: значение — константа времени компиляции без побочных состояний, а
    /// значения по умолчанию у параметров функций вычисляются в неизолированном контексте —
    /// MainActor-изолированная static let здесь не годится (Swift 6 language mode).
    nonisolated static let shortDuration: TimeInterval = 0.9
    /// F2: длинная длительность — для сообщений об отказе (onMessage). Причина отказа —
    /// не просто короткое слово, а текст, который нужно успеть прочитать.
    nonisolated static let longDuration: TimeInterval = 3.5

    func show(_ message: String, sound: Bool, visual: Bool, duration: TimeInterval = shortDuration) {
        if sound {
            NSSound(named: NSSound.Name("Tink"))?.play()
        }
        guard visual else { return }

        // F2: отменяем предыдущий отложенный dismiss ПЕРЕД планированием нового — иначе
        // короткое сообщение после длинного (или наоборот) унаследует чужой таймер.
        dismissWork?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel
        guard let label = panel.contentView?.viewWithTag(1001) as? NSTextField else { return }
        label.stringValue = message
        label.sizeToFit()

        let width = max(150, label.frame.width + 40)
        panel.setContentSize(NSSize(width: width, height: 54))
        if let screen = activeScreen() {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - width - 24, y: frame.maxY - 74))
        }
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// D8: раньше плашка всегда позиционировалась по NSScreen.main (экран с активным
    /// меню-баром/фокусом клавиатуры на уровне системы) — на многомониторной конфигурации
    /// это не обязательно тот экран, где физически работает пользователь и куда только что
    /// применилась коррекция. TypeSteady — фоновое menu bar приложение (LSUIElement) без
    /// собственных обычных окон, поэтому "активное окно" — это окно другого, фронтального
    /// приложения; надёжный источник для него — положение указателя мыши, а не
    /// NSApp.keyWindow (его у нас нет) и не NSWorkspace.frontmostApplication (даёт только
    /// приложение, не экран). NSScreen.main остаётся запасным вариантом, если экран под
    /// курсором почему-то не определился.
    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 170, height: 54),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.tag = 1001
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])
        panel.contentView = effect
        return panel
    }
}
