import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    var onToggleEnabled: (() -> Void)?
    var onToggleAutomatic: (() -> Void)?
    var onToggleTransliteration: (() -> Void)?
    var onCorrectLastWord: (() -> Void)?
    var onConvertSelection: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let settings: AppSettings
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        if let button = statusItem.button {
            button.title = ""
            button.image = StatusBarIcon.makeTemplateImage()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "TypeSteady"
            button.setAccessibilityLabel("TypeSteady")
        }
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func updateAppearance() {
        statusItem.button?.appearsDisabled = !settings.isEnabled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(toggleItem(
            title: "TypeSteady включён",
            state: settings.isEnabled,
            action: #selector(toggleEnabled)
        ))
        menu.addItem(toggleItem(
            title: "Автоисправление",
            state: settings.automaticCorrection,
            action: #selector(toggleAutomatic)
        ))
        menu.addItem(toggleItem(
            title: "Фонетический транслит",
            state: settings.transliteration,
            action: #selector(toggleTransliteration)
        ))
        menu.addItem(.separator())
        menu.addItem(item(title: "Исправить последнее слово", action: #selector(correctLastWord), key: ""))
        menu.addItem(item(title: "Преобразовать выделение", action: #selector(convertSelection), key: ""))
        menu.addItem(.separator())
        menu.addItem(item(title: "Настройки…", action: #selector(openSettings), key: ","))
        menu.addItem(item(title: "Завершить TypeSteady", action: #selector(quit), key: "q"))
        updateAppearance()
    }

    private func item(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func toggleItem(title: String, state: Bool, action: Selector) -> NSMenuItem {
        let item = self.item(title: title, action: action, key: "")
        item.state = state ? .on : .off
        return item
    }

    @objc private func toggleEnabled() { onToggleEnabled?() }
    @objc private func toggleAutomatic() { onToggleAutomatic?() }
    @objc private func toggleTransliteration() { onToggleTransliteration?() }
    @objc private func correctLastWord() { onCorrectLastWord?() }
    @objc private func convertSelection() { onConvertSelection?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
