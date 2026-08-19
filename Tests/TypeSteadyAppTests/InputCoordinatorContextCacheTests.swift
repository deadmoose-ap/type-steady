import Foundation
import Testing
@testable import TypeSteadyApp

// R6 (пост-ревью спринта 5b): cachedContext в InputCoordinator обязан иметь TTL — иначе
// граница hard deny (в т.ч. для менеджеров паролей, [SEC]) проверялась бы по устаревшему
// bundleIdentifier в окне между реальной сменой фронтального приложения и доставкой
// NSWorkspace.didActivateApplicationNotification. Тест не может детерминированно подставить
// «поддельное» фронтальное приложение в NSWorkspace, поэтому проверяет ограничение возраста
// косвенно: вручную выставляет заведомо отличимое от реального значение в кэш и наблюдает,
// свежее оно или нет.
@MainActor
struct InputCoordinatorContextCacheTests {
    private func makeCoordinator() -> InputCoordinator {
        let defaultsName = "TypeSteady.Test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)

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

    private static let staleFake = AppContext(processIdentifier: 999_999, bundleIdentifier: "test.fake.stale")

    @Test func freshCacheIsReusedWithinTTL() {
        let coordinator = makeCoordinator()
        coordinator.cachedContext = Self.staleFake
        coordinator.cachedContextTimestamp = ProcessInfo.processInfo.systemUptime

        // Кэш моложе cachedContextTTL — currentContext() обязан вернуть его как есть, не
        // перечитывая NSWorkspace.
        #expect(coordinator.currentContext() == Self.staleFake)
    }

    @Test func expiredCacheIsRecomputedAndSelfHeals() {
        let coordinator = makeCoordinator()
        coordinator.cachedContext = Self.staleFake
        // Ставим метку времени старше TTL — имитирует окно между реальной сменой
        // фронтального приложения и доставкой didActivateApplicationNotification.
        coordinator.cachedContextTimestamp = ProcessInfo.processInfo.systemUptime
            - InputCoordinator.cachedContextTTL - 0.05

        let result = coordinator.currentContext()

        // Кэш устарел — currentContext() обязан перечитать NSWorkspace напрямую и не вернуть
        // заведомо поддельное значение, которое было бы возвращено при отсутствии TTL.
        #expect(result != Self.staleFake)
        // Самовосстановление: currentContext() обновил кэш свежим значением и временем —
        // повторный вызов сразу после этого обязан вернуть тот же результат из кэша, а не
        // снова считать .staleFake устаревшим мгновенно.
        #expect(coordinator.cachedContext == result)
        #expect(
            coordinator.cachedContextTimestamp
                > ProcessInfo.processInfo.systemUptime - InputCoordinator.cachedContextTTL
        )
    }

    @Test func invalidatingCacheForcesRecomputeRegardlessOfAge() {
        let coordinator = makeCoordinator()
        coordinator.cachedContext = Self.staleFake
        coordinator.cachedContextTimestamp = ProcessInfo.processInfo.systemUptime

        // Симулирует клик мышью: handle() инвалидирует кэш контекста наравне с
        // secure-кэшем, не дожидаясь TTL.
        coordinator.handle(InputEventSnapshot(
            type: .leftMouseDown,
            keyCode: 0,
            flags: [],
            isRepeat: false,
            timestamp: 1
        ))

        #expect(coordinator.cachedContext == nil)
        #expect(coordinator.currentContext() != Self.staleFake)
    }
}
