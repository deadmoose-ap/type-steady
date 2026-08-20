import Foundation

/// E1: протокольный шов над `AccessibilityTextService`, чтобы `InputCoordinator.convert()`/
/// `performHotkeyAction()` можно было тестировать без реального AX-дерева. Сигнатуры и
/// поведение 1:1 повторяют методы `AccessibilityTextService` — сам сервис ничего не меняет,
/// только явно подписывается под протокол.
@MainActor
protocol SelectionProviding {
    func currentSelection() throws -> AccessibilitySelection
    @discardableResult
    func replace(_ selection: AccessibilitySelection, with replacement: String) throws -> Bool
    func focusedElementIsSecure() -> Bool
    func invalidateSecureCache()
}

extension AccessibilityTextService: SelectionProviding {}
