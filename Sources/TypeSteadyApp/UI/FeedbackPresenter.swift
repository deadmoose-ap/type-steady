import AppKit

@MainActor
final class FeedbackPresenter {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    func show(_ message: String, sound: Bool, visual: Bool) {
        if sound {
            NSSound(named: NSSound.Name("Tink"))?.play()
        }
        guard visual else { return }

        dismissWork?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel
        guard let label = panel.contentView?.viewWithTag(1001) as? NSTextField else { return }
        label.stringValue = message
        label.sizeToFit()

        let width = max(150, label.frame.width + 40)
        panel.setContentSize(NSSize(width: width, height: 54))
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - width - 24, y: frame.maxY - 74))
        }
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
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
