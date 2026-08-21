import Carbon
import CoreGraphics
import Foundation
import Testing
@testable import TypeSteadyApp

// R5 (пост-ревью B1): process()/флеш неоднозначной пунктуации теперь стартуют как Task из
// синхронного handle() — окно между спавном и стартом Task раньше не существовало (process()
// был синхронным). InputCoordinator.correctionPending закрывает это окно: выставляется
// синхронно перед спавном Task, и пока он true, handle() обязан игнорировать keyDown вместо
// того, чтобы кормить им TypingStateMachine.
//
// Полноценный сквозной тест через handle() с реальным успешным consume() недостижим
// детерминированно в этом окружении: layoutCatalog.activePair(settings:) зависит от реальной
// раскладки TIS, активной на машине, где запускаются тесты (KeyboardLayoutSnapshot.testLayout
// нельзя внедрить в приватные словари LayoutCatalog без нового seam'а в продакшен-коде,
// а это выходит за рамки R5). Без него ЛЮБОЙ keyDown для обычной буквы уходит в
// `guard let pair = layoutCatalog.activePair(...) else { reset(); return }` независимо от
// correctionPending — activeKeys.isEmpty была бы true в обоих случаях, и тест на этом не
// отличил бы «сработала защита R5» от «раскладка просто не настроена», то есть был бы
// психевдотестом.
//
// Вместо этого тест использует ветку хоткея-переключателя (shortcutModifiers), которая не
// зависит от LayoutCatalog вообще и лежит СРАЗУ ПОСЛЕ проверки correctionPending в handle().
// Без correctionPending эта ветка вызывает `state.invalidate(preserveLast: true)` — сохраняет
// `lastCompleted`. Проверка correctionPending, если она сработала первой, вызывает
// `state.invalidate()` (preserveLast по умолчанию false) — стирает и его. Разница в
// `lastCompleted` после вызова — детерминированный, не зависящий от TIS сигнал того, что
// именно ветка correctionPending перехватила обработку раньше остальной логики handle().
@MainActor
struct InputCoordinatorCorrectionPendingTests {
    private func makeCoordinator() -> InputCoordinator {
        let defaultsName = "TypeSteady.Test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.manualHotkey = .controlOptionSpace

        let layouts = LayoutCatalog()
        let logger = DiagnosticLogger()
        let tap = InputEventTap()
        let correction = CorrectionCoordinator(eventTap: tap, layoutCatalog: layouts, logger: logger)
        return InputCoordinator(
            settings: settings,
            layoutCatalog: layouts,
            detector: DetectionEngine(),
            correction: correction,
            accessibility: AccessibilityTextService(),
            logger: logger
        )
    }

    private func primeLastCompleted(on coordinator: InputCoordinator) {
        let context = AppContext(processIdentifier: 1, bundleIdentifier: "test")
        let letter = PhysicalKey(keyCode: 4, shift: false, capsLock: false)
        _ = coordinator.state.consume(
            key: letter, currentCharacter: "a", alternateCharacter: "ф", context: context, timestamp: 1
        )
        let completed = coordinator.state.consume(
            key: PhysicalKey(keyCode: 49, shift: false, capsLock: false),
            currentCharacter: " ",
            alternateCharacter: " ",
            context: context,
            timestamp: 2
        )
        #expect(completed != nil)
        #expect(coordinator.state.lastCompleted != nil)
    }

    private func switcherHotkeyEvent() -> InputEventSnapshot {
        InputEventSnapshot(
            type: .keyDown,
            keyCode: UInt16(kVK_Space),
            flags: [.maskControl, .maskAlternate],
            isRepeat: false,
            timestamp: 3
        )
    }

    // handle() по пути к ветке хоткея-переключателя проходит guard по currentContext():
    // если кэш пуст или устарел, currentContext() падает обратно на
    // NSWorkspace.shared.frontmostApplication — то есть на РЕАЛЬНОЕ фронтальное приложение
    // машины, где запущен тест. Если им окажется hard-denied приложение (например сам
    // TypeSteady), guard сработает раньше ветки переключателя, вызовет reset() и сотрёт
    // lastCompleted — тест начнёт флейковать в зависимости от того, что открыто на экране
    // разработчика. Подставляем в cachedContext заведомо безопасный (не hard-denied, не
    // в exclude-листе) контекст со свежей меткой времени, чтобы currentContext() гарантированно
    // вернул его из кэша и НЕ обращался к NSWorkspace — прогон теста не должен зависеть от
    // того, какое приложение фронтальное на машине.
    private func primeSafeContext(on coordinator: InputCoordinator) {
        coordinator.cachedContext = AppContext(processIdentifier: 1, bundleIdentifier: "test")
        coordinator.cachedContextTimestamp = ProcessInfo.processInfo.systemUptime
    }

    @Test func correctionPendingInterceptsBeforeSwitcherHotkeyLogic() {
        let coordinator = makeCoordinator()
        primeLastCompleted(on: coordinator)
        primeSafeContext(on: coordinator)

        coordinator.correctionPending = true
        coordinator.handle(switcherHotkeyEvent())

        // Ветка correctionPending сработала первой и вызвала state.invalidate() без
        // preserveLast — lastCompleted стёрт, хотя обычная логика хоткея-переключателя его
        // бы сохранила.
        #expect(coordinator.state.lastCompleted == nil)
        #expect(coordinator.state.activeKeys.isEmpty)
        // Флаг — состояние самого InputCoordinator, а не process(); handle() его не трогает.
        #expect(coordinator.correctionPending == true)
    }

    @Test func switcherHotkeyPreservesLastCompletedWhenNoCorrectionIsPending() {
        let coordinator = makeCoordinator()
        primeLastCompleted(on: coordinator)
        primeSafeContext(on: coordinator)

        coordinator.correctionPending = false
        coordinator.handle(switcherHotkeyEvent())

        // Базовый случай (контроль): без correctionPending обычная логика хоткея-
        // переключателя действительно доходит до state.invalidate(preserveLast: true) и
        // сохраняет lastCompleted — подтверждает, что тест выше отличает именно ветку R5,
        // а не какой-то не связанный побочный эффект.
        #expect(coordinator.state.lastCompleted != nil)
    }
}
