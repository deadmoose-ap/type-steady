import ApplicationServices
import AppKit
import Foundation

enum AccessibilityTextError: LocalizedError {
    case permissionMissing
    case noFocusedElement
    case secureField
    case noSelection
    case replacementUnsupported
    case applicationChanged

    var errorDescription: String? {
        switch self {
        case .permissionMissing: return "Нет разрешения Accessibility"
        case .noFocusedElement: return "Поле ввода недоступно через Accessibility"
        case .secureField: return "Защищённое поле"
        case .noSelection: return "Текст не выделен"
        case .replacementUnsupported: return "Приложение не разрешает заменить выделение"
        case .applicationChanged: return "Активное приложение изменилось"
        }
    }
}

struct AccessibilitySelection {
    let element: AXUIElement
    let text: String
    let context: AppContext
}

@MainActor
final class AccessibilityTextService {
    func currentSelection() throws -> AccessibilitySelection {
        guard AXIsProcessTrusted() else { throw AccessibilityTextError.permissionMissing }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw AccessibilityTextError.noFocusedElement
        }
        let context = AppContext(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier ?? "unknown"
        )
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyElementAttribute(applicationElement, kAXFocusedUIElementAttribute) else {
            throw AccessibilityTextError.noFocusedElement
        }
        if isSecure(focused) { throw AccessibilityTextError.secureField }

        var selectedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedValue)
        guard status == .success, let text = selectedValue as? String, !text.isEmpty else {
            throw AccessibilityTextError.noSelection
        }
        return AccessibilitySelection(element: focused, text: text, context: context)
    }

    func replace(_ selection: AccessibilitySelection, with replacement: String) throws -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == selection.context.processIdentifier else {
            throw AccessibilityTextError.applicationChanged
        }
        // Всегда пробуем прямую AX-запись: AXUIElementIsAttributeSettable врёт для части
        // приложений (Chromium/Electron, WebKit, часть JetBrains) — они сообщают settable=false,
        // но корректно обрабатывают AXUIElementSetAttributeValue. Спрашивать заранее — только вредить.
        let status = AXUIElementSetAttributeValue(
            selection.element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFString
        )
        return status == .success
    }

    func focusedElementIsSecure() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return true }
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyElementAttribute(applicationElement, kAXFocusedUIElementAttribute) else { return false }
        return isSecure(focused)
    }

    private func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success,
           let subrole = value as? String,
           subrole == kAXSecureTextFieldSubrole as String {
            return true
        }
        return false
    }
}
