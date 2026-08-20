import Foundation

/// E1: протокольный шов над `LayoutCatalog`, чтобы `InputCoordinator.convert()`/
/// `performHotkeyAction()` можно было тестировать без реального TIS. Сигнатуры повторяют
/// методы `LayoutCatalog` 1:1 — сам каталог ничего не меняет, только явно подписывается
/// под протокол.
@MainActor
protocol LayoutSelecting {
    func selectedPair(settings: AppSettings) -> (english: KeyboardLayoutSnapshot, russian: KeyboardLayoutSnapshot)?
    func activePair(settings: AppSettings) -> ActiveLayoutPair?
    func currentLayoutID() -> String?
    @discardableResult
    func selectLayout(id: String) async -> Bool
}

extension LayoutCatalog: LayoutSelecting {}
