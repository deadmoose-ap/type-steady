import ApplicationServices
import AppKit
import Carbon
import Foundation

enum AccessibilityTextError: LocalizedError {
    case permissionMissing
    case noFocusedElement
    case secureField
    case noSelection
    case replacementUnsupported
    case applicationChanged
    case selectionTooLarge

    var errorDescription: String? {
        switch self {
        case .permissionMissing: return "Нет разрешения Accessibility"
        case .noFocusedElement: return "Поле ввода недоступно через Accessibility"
        case .secureField: return "Защищённое поле"
        case .noSelection: return "Текст не выделен"
        case .replacementUnsupported: return "Приложение не разрешает заменить выделение"
        case .applicationChanged: return "Активное приложение изменилось"
        case .selectionTooLarge: return "Выделение слишком большое для преобразования"
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
    /// B3: без явного таймаута действует таймаут AX по умолчанию — 6 секунд. Зависшее или
    /// занятое фронтальное приложение способно застопорить главный поток на секунды при
    /// каждом обращении. 0.1 с достаточно для локального межпроцессного AX-запроса.
    private static let messagingTimeout: Float = 0.1
    /// B3: результат focusedElementIsSecure() дёргается синхронно на каждой первой клавише
    /// токена — кэшируем его на короткое время по PID, инвалидируя явно при смене
    /// активного приложения и при клике мыши (см. InputCoordinator).
    private static let secureCacheLifetime: TimeInterval = 0.5
    private var secureCache: (pid: pid_t, timestamp: TimeInterval, isSecure: Bool)?

    func currentSelection() throws -> AccessibilitySelection {
        // [SEC] Барьер должен стоять первой строкой: при активном Secure Input (Terminal с
        // Secure Keyboard Entry, системное окно авторизации) выделение вообще не должно
        // попадать в память процесса, даже до проверки subrole конкретного элемента.
        guard !IsSecureEventInputEnabled() else { throw AccessibilityTextError.secureField }
        guard AXIsProcessTrusted() else { throw AccessibilityTextError.permissionMissing }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw AccessibilityTextError.noFocusedElement
        }
        let context = AppContext(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier ?? "unknown"
        )
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, Self.messagingTimeout)
        guard let focused = copyElementAttribute(applicationElement, kAXFocusedUIElementAttribute) else {
            throw AccessibilityTextError.noFocusedElement
        }
        if isSecure(focused) { throw AccessibilityTextError.secureField }

        // C8: раньше лимит длины (C5/TypeSteadyLimits.maxConvertibleSelectionLength)
        // проверялся уже ПОСЛЕ того, как kAXSelectedTextAttribute прочитал весь текст
        // выделения в память. Здесь — попытка узнать длину диапазона заранее через
        // kAXSelectedTextRangeAttribute и отказать до чтения самого текста. Не все
        // приложения публикуют этот атрибут, поэтому при его недоступности просто идём
        // дальше обычным путём — контроль остаётся, только более поздний (проверка длины
        // в InputCoordinator.convert() как раньше остаётся окончательной страховкой).
        if let range = selectedTextRange(focused), range.length > TypeSteadyLimits.maxConvertibleSelectionLength {
            throw AccessibilityTextError.selectionTooLarge
        }

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
        let pid = app.processIdentifier
        let now = ProcessInfo.processInfo.systemUptime
        // Кэш валиден только для того же PID и не старше secureCacheLifetime — иначе
        // всегда пересчитываем, чтобы не ослаблять защиту устаревшим результатом.
        if let cache = secureCache, cache.pid == pid, now - cache.timestamp < Self.secureCacheLifetime {
            return cache.isSecure
        }
        let applicationElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(applicationElement, Self.messagingTimeout)
        guard let focused = copyElementAttribute(applicationElement, kAXFocusedUIElementAttribute) else {
            // Не удалось надёжно определить элемент — не кэшируем сомнительный результат.
            secureCache = nil
            return false
        }
        let result = isSecure(focused)
        secureCache = (pid: pid, timestamp: now, isSecure: result)
        return result
    }

    /// Сбрасывает кэш focusedElementIsSecure(). Вызывать при смене активного приложения
    /// и при клике мыши — оба события могут сменить фокусированный элемент раньше, чем
    /// истечёт secureCacheLifetime (fail closed: лучше пересчитать лишний раз, чем
    /// использовать устаревший результат).
    func invalidateSecureCache() {
        secureCache = nil
    }

    /// C8: пытается прочитать kAXSelectedTextRangeAttribute как CFRange, не читая сам текст.
    /// Возвращает nil, если приложение не публикует атрибут или его тип неожиданный —
    /// вызывающий код в этом случае просто продолжает обычным путём (см. currentSelection()).
    private func selectedTextRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // Тип уже верифицирован через CFGetTypeID — безопасное приведение, как и в
        // copyElementAttribute() ниже.
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // Тип уже верифицирован через CFGetTypeID, поэтому безопасное приведение
        // эквивалентно unsafeBitCast, но не обходит проверки ARC/типов.
        return (value as! AXUIElement)
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
