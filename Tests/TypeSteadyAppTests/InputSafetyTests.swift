import Carbon
import CoreGraphics
import Testing
@testable import TypeSteadyApp

struct InputSafetyTests {
    @Test func permissionRevocationStopsInsteadOfRepeatedlyNotifying() {
        var policy = InputEventTapDisablePolicy()

        let first = policy.notification(for: .tapDisabledByUserInput)
        let repeated = policy.notification(for: .tapDisabledByUserInput)
        let differentRepeat = policy.notification(for: .tapDisabledByTimeout)
        #expect(first == .permissionOrUserInput)
        #expect(repeated == nil)
        #expect(differentRepeat == nil)

        policy.reset()
        let afterReset = policy.notification(for: .tapDisabledByTimeout)
        #expect(afterReset == .timeout)
    }

    @Test func ordinaryEventsDoNotConsumeDisableNotification() {
        var policy = InputEventTapDisablePolicy()
        let ordinary = policy.notification(for: .keyDown)
        let disabled = policy.notification(for: .tapDisabledByUserInput)
        #expect(ordinary == nil)
        #expect(disabled == .permissionOrUserInput)
    }

    @Test func optionOnlyTriggersOnCleanRelease() {
        var recognizer = ModifierOnlyHotkeyRecognizer()

        let armed = recognizer.consume(snapshot(type: .flagsChanged, flags: [.maskAlternate]), enabled: true)
        let released = recognizer.consume(snapshot(type: .flagsChanged, flags: []), enabled: true)
        let repeatedRelease = recognizer.consume(snapshot(type: .flagsChanged, flags: []), enabled: true)
        #expect(!armed)
        #expect(released)
        #expect(!repeatedRelease)
    }

    @Test func optionOnlyCancelsWhenAnotherKeyIsPressed() {
        var recognizer = ModifierOnlyHotkeyRecognizer()

        let armed = recognizer.consume(snapshot(type: .flagsChanged, flags: [.maskAlternate]), enabled: true)
        let keyPressed = recognizer.consume(
            snapshot(type: .keyDown, keyCode: UInt16(kVK_ANSI_A), flags: [.maskAlternate]),
            enabled: true
        )
        let released = recognizer.consume(snapshot(type: .flagsChanged, flags: []), enabled: true)
        #expect(!armed)
        #expect(!keyPressed)
        #expect(!released)
    }

    @Test func optionOnlyCancelsWhenCombinedWithAnotherModifier() {
        var recognizer = ModifierOnlyHotkeyRecognizer()

        let armed = recognizer.consume(snapshot(type: .flagsChanged, flags: [.maskAlternate]), enabled: true)
        let combined = recognizer.consume(
            snapshot(type: .flagsChanged, flags: [.maskAlternate, .maskCommand]),
            enabled: true
        )
        let released = recognizer.consume(snapshot(type: .flagsChanged, flags: []), enabled: true)
        #expect(!armed)
        #expect(!combined)
        #expect(!released)
    }

    @Test func disabledOptionOnlyNeverTriggers() {
        var recognizer = ModifierOnlyHotkeyRecognizer()

        let pressed = recognizer.consume(snapshot(type: .flagsChanged, flags: [.maskAlternate]), enabled: false)
        let released = recognizer.consume(snapshot(type: .flagsChanged, flags: []), enabled: false)
        #expect(!pressed)
        #expect(!released)
    }

    // B2: если beginCorrectionGate() не сопровождается штатным finishCorrectionGate()
    // (например, краш/зависание между begin и defer в CorrectionCoordinator), watchdog
    // обязан закрыть gate принудительно — иначе клавиатура перестанет работать во всех
    // приложениях, пока TypeSteady не будет убит. Дедлайн watchdog'а — 3 с (поднят в R3
    // пост-ревью спринта 3, см. InputEventTap.correctionGateWatchdogTimeout), поэтому тест
    // сознательно ждёт дольше.
    @Test func watchdogForceClosesAbandonedGate() async {
        let tap = InputEventTap()
        await confirmation("gate force-closed by watchdog") { confirmed in
            tap.onGateForceClosed = { dropped in
                #expect(dropped == 0)
                confirmed()
            }
            tap.beginCorrectionGate()
            // Намеренно не вызываем finishCorrectionGate() — имитация зависшего пути.
            try? await Task.sleep(nanoseconds: 3_300_000_000)
        }
    }

    // B2: после принудительного закрытия gate последующий штатный цикл
    // begin/finishCorrectionGate обязан отработать нормально — isGating не должен
    // "залипнуть" в true.
    @Test func gateReopensNormallyAfterForcedClosure() async {
        let tap = InputEventTap()
        await confirmation("gate force-closed by watchdog") { confirmed in
            tap.onGateForceClosed = { _ in confirmed() }
            tap.beginCorrectionGate()
            try? await Task.sleep(nanoseconds: 3_300_000_000)
        }

        var replayed = false
        tap.beginCorrectionGate()
        tap.finishCorrectionGate { _ in replayed = true }
        #expect(!replayed) // очередь пуста — replay не вызывается, но и не зависает.
    }

    // R3 (пост-ревью спринта 3): watchdog — аварийный клапан против мёртвого/зависшего gate,
    // а не ограничитель производительности. Легитимная операция (например,
    // replaceSelectionFallback на границе лимита C5 — до ~1 с одних пауз между чанками)
    // не должна быть прервана раньше времени. Ждём заметно дольше старого таймаута (1 с),
    // но меньше нового (3 с), и проверяем, что force-close не сработал и штатное закрытие
    // gate потом отрабатывает без потери событий (replay не вызывается на пустой очереди).
    @Test func legitimateLongGateIsNotClosedEarlyByWatchdog() async {
        final class ForceClosedFlag: @unchecked Sendable {
            var value = false
        }
        let flag = ForceClosedFlag()
        let tap = InputEventTap()
        tap.onGateForceClosed = { _ in flag.value = true }

        tap.beginCorrectionGate()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(!flag.value)

        var replayed = false
        tap.finishCorrectionGate { _ in replayed = true }
        #expect(!replayed)

        // Дождаться момента, когда сработал бы старый (уже отменённый finishCorrectionGate)
        // watchdog, и убедиться, что force-close не произошёл задним числом.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(!flag.value)
    }

    private func snapshot(
        type: CGEventType,
        keyCode: UInt16 = UInt16(kVK_Option),
        flags: CGEventFlags
    ) -> InputEventSnapshot {
        InputEventSnapshot(
            type: type,
            keyCode: keyCode,
            flags: flags,
            isRepeat: false,
            timestamp: 1
        )
    }
}
