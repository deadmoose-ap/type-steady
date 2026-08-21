import AppKit
import SwiftUI

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general
    case languages
    case detection
    case applications
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Основные"
        case .languages: return "Языки"
        case .detection: return "Распознавание"
        case .applications: return "Приложения"
        case .privacy: return "Приватность"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Поведение, горячие клавиши и запуск"
        case .languages: return "Активная пара системных раскладок"
        case .detection: return "Точность и пользовательские правила"
        case .applications: return "Профили приложений и исключения"
        case .privacy: return "Разрешения и локальная диагностика"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .languages: return "character.book.closed"
        case .detection: return "text.magnifyingglass"
        case .applications: return "square.grid.2x2"
        case .privacy: return "hand.raised"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var layouts: LayoutCatalog
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    let refreshLayouts: () -> Void
    let restartMonitor: () -> Void

    @State private var selection: SettingsDestination? = .general
    @State private var showsPermissionRepairConfirmation = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 560)
        .confirmationDialog(
            "Сбросить разрешения TypeSteady?",
            isPresented: $showsPermissionRepairConfirmation,
            titleVisibility: .visible
        ) {
            Button("Сбросить и запросить заново", role: .destructive) {
                permissions.repairStaleRecords()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будут удалены только записи Accessibility и Input Monitoring для TypeSteady. После этого macOS попросит подтвердить их заново.")
        }
    }

    private var sidebar: some View {
        List(SettingsDestination.allCases, selection: $selection) { destination in
            Label(destination.title, systemImage: destination.systemImage)
                .tag(destination)
                .accessibilityIdentifier("settings.sidebar.\(destination.rawValue)")
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Работает локально", systemImage: "checkmark.shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Aleksei Panin")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    Link("GitHub", destination: URL(string: "https://github.com/deadmoose-ap")!)
                    Text("·").foregroundStyle(.tertiary)
                    Link("LinkedIn", destination: URL(string: "https://www.linkedin.com/in/aleksei-panin/")!)
                }
                .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var detail: some View {
        let destination = selection ?? .general

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(destination)
                page(for: destination)
            }
            .frame(maxWidth: 720, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .accessibilityIdentifier("settings.detail.\(destination.rawValue)")
    }

    private func pageHeader(_ destination: SettingsDestination) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(destination.title)
                .font(.system(size: 27, weight: .semibold))
            Text(destination.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func page(for destination: SettingsDestination) -> some View {
        switch destination {
        case .general:
            generalPage
        case .languages:
            languagesPage
        case .detection:
            detectionPage
        case .applications:
            applicationsPage
        case .privacy:
            privacyPage
        }
    }

    private var generalPage: some View {
        VStack(spacing: 16) {
            masterControl

            SettingsCard(title: "Работа", systemImage: "bolt") {
                SettingToggleRow(
                    title: "Автоматически исправлять последнее слово",
                    detail: "Исправление выполняется после пробела или знака препинания.",
                    isOn: $settings.automaticCorrection
                )
                SettingsDivider()
                SettingToggleRow(
                    title: "Преобразовывать выделенный текст",
                    detail: "Явное преобразование по горячей клавише или через menu bar.",
                    isOn: $settings.selectionConversion
                )
                SettingsDivider()
                SettingToggleRow(
                    title: "Звуковой сигнал",
                    detail: "Системный звук после успешной операции.",
                    isOn: $settings.soundFeedback
                )
                SettingsDivider()
                SettingToggleRow(
                    title: "Визуальный сигнал",
                    detail: "Короткий индикатор направления исправления.",
                    isOn: $settings.visualFeedback
                )
            }

            SettingsCard(title: "Горячие клавиши", systemImage: "keyboard") {
                LabeledContent("Действие с текстом") {
                    AdaptiveGlassPicker(
                        title: "Действие с текстом",
                        selection: $settings.manualHotkey,
                        options: HotkeyChoice.allCases.map {
                            SettingsSelectionOption(value: $0, title: $0.title)
                        },
                        width: 165
                    )
                }
                SettingsDivider()
                NoteText("\(settings.manualHotkey.title) преобразует выделенный текст. Если выделения нет — исправляет последнее слово или отменяет последнее исправление. Вариант «⌥ Option» срабатывает после отпускания Option, только если вместе с ним не нажималась другая клавиша.")
            }

            SettingsCard(title: "Запуск", systemImage: "power") {
                SettingToggleRow(
                    title: "Запускать при входе",
                    detail: "TypeSteady появится в menu bar после входа в macOS.",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                if launchAtLogin.requiresApproval {
                    SettingsDivider()
                    StatusMessage(
                        text: "macOS ожидает подтверждения login item в System Settings.",
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
                if let error = launchAtLogin.lastError {
                    SettingsDivider()
                    StatusMessage(text: error, systemImage: "xmark.circle.fill", color: .red)
                }
            }
        }
    }

    private var masterControl: some View {
        AdaptiveGlassPanel {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(settings.isEnabled ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                    Image(systemName: settings.isEnabled ? "waveform.path" : "pause.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(settings.isEnabled ? Color.accentColor : Color.secondary)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.isEnabled ? "TypeSteady включён" : "TypeSteady приостановлен")
                        .font(.headline)
                    Text(settings.isEnabled ? "Переключение раскладки работает в фоне" : "Мониторинг ввода временно остановлен")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Toggle("TypeSteady включён", isOn: $settings.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .accessibilityIdentifier("settings.masterToggle")
            }
        }
    }

    private var languagesPage: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Пара раскладок", systemImage: "character.book.closed") {
                LabeledContent("English") {
                    AdaptiveGlassPicker(
                        title: "English",
                        selection: $settings.englishLayoutID,
                        options: layouts.descriptors
                            .filter { $0.languageCode == .english }
                            .map { SettingsSelectionOption(value: $0.id, title: $0.name) },
                        width: 260
                    )
                }
                SettingsDivider()
                LabeledContent("Русская") {
                    AdaptiveGlassPicker(
                        title: "Русская",
                        selection: $settings.russianLayoutID,
                        options: layouts.descriptors
                            .filter { $0.languageCode == .russian }
                            .map { SettingsSelectionOption(value: $0.id, title: $0.name) },
                        width: 260
                    )
                }
                SettingsDivider()
                HStack {
                    NoteText("Используются установленные input sources macOS.")
                    Spacer()
                    AdaptiveActionButton(title: "Обновить", systemImage: "arrow.clockwise", action: refreshLayouts)
                }
                if let error = layouts.lastError {
                    SettingsDivider()
                    StatusMessage(text: error, systemImage: "xmark.circle.fill", color: .red)
                }
            }

            SettingsCard(title: "Расширяемая архитектура", systemImage: "point.3.connected.trianglepath.dotted") {
                NoteText("Движок строит карту из input sources macOS. Новые языковые профили можно добавлять без изменения мониторинга ввода.")
            }
        }
    }

    private var detectionPage: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Автоматическое решение", systemImage: "scope") {
                LabeledContent("Режим") {
                    AdaptiveGlassPicker(
                        title: "Режим",
                        selection: $settings.aggressiveness,
                        options: DetectionAggressiveness.allCases.map {
                            SettingsSelectionOption(value: $0, title: $0.title)
                        },
                        width: 220
                    )
                }
                SettingsDivider()
                SettingToggleRow(
                    title: "Исправлять фонетический транслит",
                    detail: "Например, privet → привет.",
                    isOn: $settings.transliteration
                )
            }

            SettingsCard(title: "Всегда исправлять", systemImage: "arrow.triangle.2.circlepath") {
                RulesEditor(
                    text: $settings.alwaysConvert,
                    accessibilityIdentifier: "settings.alwaysConvert",
                    help: "Одно исходное слово на строку."
                )
            }

            SettingsCard(title: "Никогда не исправлять", systemImage: "hand.raised") {
                RulesEditor(
                    text: $settings.neverConvert,
                    accessibilityIdentifier: "settings.neverConvert",
                    help: "Одно слово или термин на строку. В многословном термине защищается каждое слово; регистр не учитывается."
                )
            }

            Label("В собственном окне TypeSteady автозамена полностью отключена.", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var applicationsPage: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "IDE и редакторы", systemImage: "chevron.left.forwardslash.chevron.right") {
                SettingToggleRow(
                    title: "Строгий профиль для кода",
                    detail: "URL, пути, camelCase, snake_case, токены с цифрами и известные технические слова пропускаются.",
                    isOn: $settings.strictCodeEditors
                )
            }

            SettingsCard(title: "Исключённые bundle identifiers", systemImage: "nosign") {
                RulesEditor(
                    text: $settings.excludedBundleIDs,
                    accessibilityIdentifier: "settings.excludedBundleIDs",
                    minHeight: 190,
                    help: "Одно значение на строку. Password managers всегда исключены независимо от этого списка."
                )
            }
        }
    }

    private var privacyPage: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Системные разрешения", systemImage: "lock.shield") {
                permissionRow(
                    title: "Accessibility",
                    detail: "Нужно для преобразования выделенного текста.",
                    granted: permissions.accessibilityGranted,
                    request: permissions.requestAccessibility,
                    open: permissions.openAccessibilitySettings
                )
                SettingsDivider()
                permissionRow(
                    title: "Input Monitoring",
                    detail: "Нужно для определения физически нажатых клавиш.",
                    granted: permissions.inputMonitoringGranted,
                    request: permissions.requestInputMonitoring,
                    open: permissions.openInputMonitoringSettings
                )
                SettingsDivider()
                HStack {
                    NoteText("macOS всегда требует ручного подтверждения. После него может потребоваться перезапуск монитора.")
                    Spacer()
                    AdaptiveActionButton(
                        title: "Проверить снова",
                        systemImage: "arrow.clockwise",
                        action: {
                            permissions.refresh()
                            restartMonitor()
                        }
                    )
                }
                if !permissions.accessibilityGranted || !permissions.inputMonitoringGranted {
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        NoteText("Если TypeSteady уже включён в macOS, но здесь разрешение не распознано, запись относится к предыдущей тестовой сборке.")
                        HStack {
                            if let message = permissions.repairMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            AdaptiveActionButton(
                                title: "Исправить старые записи",
                                systemImage: "wrench.and.screwdriver",
                                action: { showsPermissionRepairConfirmation = true }
                            )
                        }
                    }
                }
            }

            SettingsCard(title: "Диагностика", systemImage: "waveform.badge.magnifyingglass") {
                SettingToggleRow(
                    title: "Локальные обезличенные события",
                    detail: "Набранный текст, выделение и key codes никогда не журналируются.",
                    isOn: $settings.diagnostics
                )
            }

            SettingsCard(title: "Локальная обработка", systemImage: "network.slash") {
                Label("Сетевых запросов, телеметрии и отправки crash-отчётов в приложении нет.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        request: @escaping () -> Void,
        open: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(granted ? Color.green : Color.orange)
                .frame(width: 24)
                .accessibilityLabel("\(title): \(granted ? "разрешено" : "требуется")")
                .help(granted ? "Разрешено" : "Требуется")

            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if !granted {
                    AdaptiveActionButton(title: "Разрешить", prominent: true, action: request)
                }
                AdaptiveActionButton(title: "Открыть настройки", systemImage: "arrow.up.forward.app", action: open)
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            shape
                .fill(.thinMaterial)
                .overlay {
                    shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.32))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
        }
    }
}

private struct SettingToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 18)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
        }
    }
}

private struct RulesEditor: View {
    @Binding var text: String
    let accessibilityIdentifier: String
    var minHeight: CGFloat = 110
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: minHeight)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
                .accessibilityIdentifier(accessibilityIdentifier)
            NoteText(help)
        }
    }
}

private struct NoteText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StatusMessage: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().opacity(0.65)
    }
}

private struct SettingsSelectionOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }
}

private struct AdaptiveGlassPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [SettingsSelectionOption<Value>]
    let width: CGFloat

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? "—"
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            menu
                .menuStyle(.button)
                .buttonStyle(.glass)
                .controlSize(.regular)
                .frame(width: width)
        } else {
            menu
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(width: width)
        }
    }

    private var menu: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    if selection == option.value {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Text(selectedTitle)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
    }
}

private struct AdaptiveGlassPanel<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            content
                .padding(16)
                .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            content
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                }
        }
    }
}

private struct AdaptiveActionButton: View {
    let title: String
    var systemImage: String?
    var prominent = false
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.action = action
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            if prominent {
                Button(action: action) { label }
                    .buttonStyle(.glassProminent)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.glass)
            }
        } else {
            if prominent {
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            }
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(rootView: SettingsView) {
        let hosting = NSHostingController(rootView: rootView)
        let materialView = NSVisualEffectView()
        let container = NSViewController()
        let window: NSWindow
        let toolbar = NSToolbar(identifier: "TypeSteady.SettingsToolbar")

        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active

        container.view = materialView
        container.addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: materialView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: materialView.bottomAnchor)
        ])

        window = NSWindow(contentViewController: container)

        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly

        window.title = "TypeSteady"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 860, height: 620))
        window.minSize = NSSize(width: 780, height: 560)
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
