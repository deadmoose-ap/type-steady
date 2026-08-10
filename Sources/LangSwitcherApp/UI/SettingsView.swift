import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var layouts: LayoutCatalog
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    let refreshLayouts: () -> Void
    let restartMonitor: () -> Void

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Основные", systemImage: "switch.2") }
            languagesTab
                .tabItem { Label("Языки", systemImage: "character.book.closed") }
            detectionTab
                .tabItem { Label("Распознавание", systemImage: "text.magnifyingglass") }
            applicationsTab
                .tabItem { Label("Приложения", systemImage: "square.grid.2x2") }
            privacyTab
                .tabItem { Label("Приватность", systemImage: "hand.raised") }
        }
        .padding(16)
        .frame(width: 650, height: 530)
    }

    private var generalTab: some View {
        Form {
            Section("Работа") {
                Toggle("Lang Switcher включён", isOn: $settings.isEnabled)
                Toggle("Автоматически исправлять последнее слово", isOn: $settings.automaticCorrection)
                Toggle("Преобразовывать выделенный текст", isOn: $settings.selectionConversion)
                Toggle("Звуковой сигнал", isOn: $settings.soundFeedback)
                Toggle("Визуальный сигнал", isOn: $settings.visualFeedback)
            }
            Section("Горячие клавиши") {
                Picker("Последнее слово", selection: $settings.manualHotkey) {
                    ForEach(HotkeyChoice.allCases) { choice in Text(choice.title).tag(choice) }
                }
                Text("Преобразование выделения: \(settings.manualHotkey.selectionTitle). К базовой комбинации добавляется Command, а при конфликте — Control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Запуск") {
                Toggle(
                    "Запускать при входе",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                if launchAtLogin.requiresApproval {
                    Text("macOS ожидает подтверждения login item в System Settings.")
                        .foregroundStyle(.orange)
                }
                if let error = launchAtLogin.lastError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var languagesTab: some View {
        Form {
            Section("Пара раскладок") {
                Picker("English", selection: $settings.englishLayoutID) {
                    ForEach(layouts.descriptors.filter { $0.languageCode == .english }) {
                        Text($0.name).tag($0.id)
                    }
                }
                Picker("Русская", selection: $settings.russianLayoutID) {
                    ForEach(layouts.descriptors.filter { $0.languageCode == .russian }) {
                        Text($0.name).tag($0.id)
                    }
                }
                Button("Обновить раскладки", action: refreshLayouts)
                if let error = layouts.lastError { Text(error).foregroundStyle(.red) }
            }
            Text("Движок строит карту из input sources macOS. Архитектура допускает добавление новых языковых профилей без изменения мониторинга ввода.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var detectionTab: some View {
        Form {
            Section("Автоматическое решение") {
                Picker("Режим", selection: $settings.aggressiveness) {
                    ForEach(DetectionAggressiveness.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Исправлять фонетический транслит", isOn: $settings.transliteration)
            }
            Section("Всегда исправлять") {
                TextEditor(text: $settings.alwaysConvert)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 90)
                Text("Одно исходное слово на строку.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Никогда не исправлять") {
                TextEditor(text: $settings.neverConvert)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 90)
            }
        }
        .formStyle(.grouped)
    }

    private var applicationsTab: some View {
        Form {
            Section("IDE и редакторы") {
                Toggle("Строгий профиль для кода", isOn: $settings.strictCodeEditors)
                Text("URL, пути, camelCase, snake_case, токены с цифрами и известные технические слова пропускаются.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Исключённые bundle identifiers") {
                TextEditor(text: $settings.excludedBundleIDs)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                Text("Одно значение на строку. Password managers всегда исключены независимо от этого списка.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var privacyTab: some View {
        Form {
            permissionRow(
                title: "Accessibility",
                granted: permissions.accessibilityGranted,
                request: permissions.requestAccessibility,
                open: permissions.openAccessibilitySettings
            )
            permissionRow(
                title: "Input Monitoring",
                granted: permissions.inputMonitoringGranted,
                request: permissions.requestInputMonitoring,
                open: permissions.openInputMonitoringSettings
            )
            Button("Обновить состояние и перезапустить монитор") {
                permissions.refresh()
                restartMonitor()
            }
            Section("Диагностика") {
                Toggle("Локальные обезличенные события", isOn: $settings.diagnostics)
                Text("Набранный текст, выделение и key codes никогда не журналируются. Сетевых запросов в приложении нет.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        granted: Bool,
        request: @escaping () -> Void,
        open: @escaping () -> Void
    ) -> some View {
        Section(title) {
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Text(granted ? "Разрешено" : "Требуется разрешение")
                Spacer()
                Button("Запросить", action: request)
                Button("System Settings", action: open)
            }
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(rootView: SettingsView) {
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Lang Switcher"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 650, height: 530))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
