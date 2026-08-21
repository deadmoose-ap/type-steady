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
        // Раньше здесь была confirmation(...) с фиксированной паузой в 3.3 с (3.0 с реального
        // watchdog'а + 300 мс "запаса" на доставку notifyGateForceClosed() через
        // DispatchQueue.main.async). Тот же класс бомбы замедленного действия, что и в
        // finishCorrectionGateForceClosesWhenReplayKeepsRefillingQueue выше по файлу — просто
        // с более широким запасом: confirmation() не ждёт confirmed() дольше времени жизни
        // своего closure, так что если main queue занята дольше 300 мс параллельными
        // @MainActor-тестами, confirmed() не успевает — тест падает не по существу.
        // Реальные 3 с ожидания самого watchdog'а — неизбежная и корректная часть теста (мы
        // проверяем именно продакшен-таймер), но окно ОЖИДАНИЯ уведомления не должно зависеть
        // от точной длины паузы — ждём событие через continuation с большим страховочным
        // таймаутом на случай, если уведомление не придёт вовсе (регрессия).
        let dropped: Int? = await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let gate = SingleResumeGate(continuation)
            tap.onGateForceClosed = { dropped in gate.resumeOnce(with: dropped) }
            tap.beginCorrectionGate()
            // Намеренно не вызываем finishCorrectionGate() — имитация зависшего пути.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 8) {
                gate.resumeOnce(with: nil)
            }
        }
        #expect(dropped != nil)
        #expect(dropped == 0)
    }

    // B2: после принудительного закрытия gate последующий штатный цикл
    // begin/finishCorrectionGate обязан отработать нормально — isGating не должен
    // "залипнуть" в true.
    @Test func gateReopensNormallyAfterForcedClosure() async {
        let tap = InputEventTap()
        let dropped: Int? = await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let gate = SingleResumeGate(continuation)
            tap.onGateForceClosed = { dropped in gate.resumeOnce(with: dropped) }
            tap.beginCorrectionGate()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 8) {
                gate.resumeOnce(with: nil)
            }
        }
        #expect(dropped != nil)

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

    // E2: ветка дедлайна/лимита итераций finishCorrectionGate() — отдельная от watchdog'а
    // выше (B11/B2): здесь gate закрывается штатным вызовом finishCorrectionGate(), но
    // replay-очередь пополняется быстрее, чем опустошается (стресс-тест непрерывного
    // потока событий), и цикл обязан прерваться сам, не крутясь на MainActor бесконечно.
    // capturedEvents в продакшене наполняется только fileprivate handle() внутри реального
    // CGEventTap — недостижимо из теста. testBeginGate()/testAppendCapturedEvent() — минимальный
    // internal-шов (см. комментарий над ним в InputEventTap.swift), который наполняет ту же
    // очередь тем же способом, не трогая сам callback tap'а.
    // Счётчик итераций replay — пишется исключительно синхронно внутри тела finishCorrectionGate
    // (до точки await), а читается уже после того, как withCheckedContinuation резюмировалась.
    // Резюме continuation — точка синхронизации (happens-before), поэтому отдельный lock тут
    // не нужен: тот же паттерн "класс-обёртка без лока", что и у ForceClosedFlag ниже по файлу.
    private final class IterationCounter: @unchecked Sendable {
        var value = 0
    }

    // Защита от двойного резюма continuation: onGateForceClosed в этом тесте физически может
    // сработать только один раз (testBeginGate() намеренно не взводит watchdog — см. комментарий
    // над testBeginGate() в InputEventTap.swift, поэтому сюда долетает только уведомление из
    // самого finishCorrectionGate()). Но резюмировать continuation дважды — это краш, а не
    // падение теста, поэтому guard оставлен на случай будущей регрессии в продакшен-коде
    // (например, если watchdog и дедлайн когда-нибудь начнут стрелять оба).
    private final class SingleResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        private let continuation: CheckedContinuation<Int?, Never>

        init(_ continuation: CheckedContinuation<Int?, Never>) {
            self.continuation = continuation
        }

        func resumeOnce(with value: Int?) {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            continuation.resume(returning: value)
        }
    }

    @Test func finishCorrectionGateForceClosesWhenReplayKeepsRefillingQueue() async {
        let tap = InputEventTap()
        let event = CapturedInputEvent(type: .keyDown, keyCode: 0, flags: [], isRepeat: false)

        tap.testBeginGate()
        tap.testAppendCapturedEvent(event)

        let replayIterations = IterationCounter()

        // notifyGateForceClosed() постит уведомление на main queue асинхронно, а suite гоняется
        // параллельно с другими @MainActor-тестами — фиксированная пауза (было: 50 мс) не
        // гарантирует, что очередь main queue успеет отработать под нагрузкой (наблюдалось
        // ~37% падений на восьми последовательных прогонах). Вместо паузы ждём само событие
        // через continuation.
        //
        // Намеренно НЕ withTaskGroup с гонкой Task.sleep: если реальное уведомление так и не
        // придёт (регрессия в продакшен-коде), дочерняя задача с withCheckedContinuation внутри
        // группы останется подвешенной навсегда — CheckedContinuation не резюмируется сам по
        // себе от cancelAll(). withTaskGroup перед возвратом результата структурно обязан
        // дождаться завершения ВСЕХ дочерних задач, поэтому такая группа зависла бы точно так
        // же, как зависал бы тест без таймаута вовсе — просто заменяя один вид зависания другим.
        // Вместо этого используем один-единственный continuation, который может резюмировать
        // ЛЮБАЯ из двух сторон — реальный колбэк (main queue) или страховочный таймер (глобальная
        // очередь) — SingleResumeGate гарантирует ровно одно резюме, какая бы сторона ни
        // сработала первой. Ни одна сторона не создаёт структурную задачу, которую пришлось бы
        // потом ждать, — зависание невозможно в принципе.
        let forceClosed: Int? = await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let gate = SingleResumeGate(continuation)
            tap.onGateForceClosed = { dropped in gate.resumeOnce(with: dropped) }
            tap.finishCorrectionGate { batch in
                replayIterations.value += 1
                // Эмулирует непрерывный поток пользовательского набора во время replay —
                // очередь никогда не пустеет сама, поэтому цикл обязан прерваться по
                // correctionGateMaxIterations (200) или correctionGateDeadline (0.25 с),
                // а не крутиться неограниченно.
                for event in batch { tap.testAppendCapturedEvent(event) }
            }
            // Страховочный таймаут: на порядки больше ожидаемого пути (correctionGateDeadline
            // 0.25 с + доставка на main queue), но конечный — если уведомление не придёт вовсе,
            // тест обязан упасть по #expect(forceClosed != nil) ниже, а не висеть.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5) {
                gate.resumeOnce(with: nil)
            }
        }

        #expect(replayIterations.value > 0)
        // Принудительное закрытие обязано было сработать (и о нём обязано было прийти
        // уведомление) — иначе цикл действительно крутился бы неограниченно.
        #expect(forceClosed != nil)
        #expect((forceClosed ?? 0) > 0)

        // Gate не должен "залипнуть" — последующий штатный цикл begin/finish отрабатывает
        // нормально, очередь пуста, replay не вызывается.
        var replayedAfter = false
        tap.beginCorrectionGate()
        tap.finishCorrectionGate { _ in replayedAfter = true }
        #expect(!replayedAfter)
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
