import AppKit
import CoreGraphics
import Foundation

let typeSteadyEventMarker: Int64 = 0x54_53_54_44

struct InputEventSnapshot: Sendable {
    let type: CGEventType
    let keyCode: UInt16
    let flags: CGEventFlags
    let isRepeat: Bool
    let timestamp: TimeInterval
}

struct CapturedInputEvent: Sendable {
    let type: CGEventType
    let keyCode: UInt16
    let flags: CGEventFlags
    let isRepeat: Bool
}

enum InputEventTapDisableReason: Equatable, Sendable {
    case timeout
    case permissionOrUserInput
}

struct InputEventTapDisablePolicy {
    private var didNotify = false

    mutating func notification(for type: CGEventType) -> InputEventTapDisableReason? {
        let reason: InputEventTapDisableReason
        switch type {
        case .tapDisabledByTimeout:
            reason = .timeout
        case .tapDisabledByUserInput:
            reason = .permissionOrUserInput
        default:
            return nil
        }
        guard !didNotify else { return nil }
        didNotify = true
        return reason
    }

    mutating func reset() {
        didNotify = false
    }
}

final class InputEventTap: @unchecked Sendable {
    var onEvent: ((InputEventSnapshot) -> Void)?
    var onTapDisabled: ((InputEventTapDisableReason) -> Void)?
    /// Correction gate закрылся принудительно (watchdog или дедлайн итераций), а не
    /// штатным опустошением очереди — см. code review B2. Аргумент — число отброшенных событий.
    var onGateForceClosed: ((Int) -> Void)?

    /// B2: верхняя граница на цикл воспроизведения захваченных событий в finishCorrectionGate —
    /// без неё быстрый набор во время воспроизведения мог бы крутить цикл на MainActor неограниченно.
    private static let correctionGateDeadline: TimeInterval = 0.25
    private static let correctionGateMaxIterations = 200
    /// B2: если gate не закрыт штатно за это время после beginCorrectionGate() (например,
    /// краш/зависание между begin и defer в CorrectionCoordinator), watchdog закрывает его
    /// принудительно — иначе клавиатура перестанет работать во всех приложениях.
    ///
    /// R3 (пост-ревью спринта 3): это аварийный клапан против мёртвого/зависшего gate, а не
    /// ограничитель производительности — обязан стоять заведомо выше любого легитимного
    /// времени работы. Худший легитимный случай — replaceSelectionFallback() с выделением
    /// на границе лимита C5 (InputCoordinator.maxConvertibleSelectionLength = 5000 символов):
    /// не-BMP текст (эмодзи и т.п., 2 UTF-16 unit на символ) даёт 500 чанков по
    /// chunkUTF16(maximumCodeUnits: 20) и Thread.sleep(0.002) между ними — уже ~1 с одних
    /// только пауз, не считая самой инъекции. Если C5-лимит или размер чанка когда-нибудь
    /// увеличат, этот таймаут нужно пересмотреть вместе с ними.
    private static let correctionGateWatchdogTimeout: TimeInterval = 3.0

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var isGating = false
    private var capturedEvents: [CapturedInputEvent] = []
    private var disablePolicy = InputEventTapDisablePolicy()
    /// B2: watchdog-таймер, запускаемый на отдельной очереди (не на MainActor), чтобы
    /// сработать, даже если MainActor завис между beginCorrectionGate() и defer.
    private var watchdogWorkItem: DispatchWorkItem?
    /// B7: сигнализируется рабочим потоком tap'а по выходу из CFRunLoopRun(). start(),
    /// вызванный сразу после stop(), ждёт его недолго, чтобы не создать второй tap и
    /// второй поток, пока первый ещё разбирается.
    private var runLoopExited: DispatchSemaphore?

    @discardableResult
    func start() -> Bool {
        lock.lock()
        guard tap == nil else { lock.unlock(); return true }
        let pendingExit = runLoopExited
        lock.unlock()
        // Дождаться завершения предыдущего рабочего потока, если stop() ещё не успел
        // его остановить полностью (см. B7). Ограниченное ожидание — не блокируем
        // MainActor надолго, если что-то пошло не так.
        if let pendingExit {
            _ = pendingExit.wait(timeout: .now() + 0.2)
        }

        lock.lock()
        defer { lock.unlock() }
        guard tap == nil else { return true }
        disablePolicy.reset()

        let mask: CGEventMask = [
            CGEventType.keyDown,
            .keyUp,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ].reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: typeSteadyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        tap = eventTap
        let exitSemaphore = DispatchSemaphore(value: 0)
        runLoopExited = exitSemaphore
        let worker = Thread { [weak self] in
            self?.runEventLoop(eventTap)
            exitSemaphore.signal()
        }
        worker.name = "TypeSteady.InputEventTap"
        worker.qualityOfService = .userInteractive
        thread = worker
        worker.start()
        return true
    }

    func stop() {
        lock.lock()
        let currentTap = tap
        let currentRunLoop = runLoop
        tap = nil
        isGating = false
        capturedEvents.removeAll()
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
        lock.unlock()

        if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: false) }
        if let currentRunLoop { CFRunLoopStop(currentRunLoop) }
    }

    func beginCorrectionGate() {
        // R4: work item создаётся до захвата лока (никаких вызовов lock изнутри — DispatchWorkItem
        // сам по себе не трогает self.lock), но запись в watchdogWorkItem идёт в одной локированной
        // секции с isGating/capturedEvents — единая дисциплина NSLock для всего состояния gate.
        let work = DispatchWorkItem { [weak self] in self?.forceCloseGateIfNeeded() }
        lock.lock()
        capturedEvents.removeAll(keepingCapacity: true)
        isGating = true
        watchdogWorkItem = work
        lock.unlock()

        DispatchQueue.global(qos: .userInteractive).asyncAfter(
            deadline: .now() + Self.correctionGateWatchdogTimeout,
            execute: work
        )
    }

    func finishCorrectionGate(replay: ([CapturedInputEvent]) -> Void) {
        // R4: та же дисциплина — cancel() только помечает work item отменённым и не ждёт
        // уже выполняющийся блок, так что держать его под lock.lock()/unlock() безопасно
        // (никакой попытки взять lock повторно из cancel() нет).
        lock.lock()
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
        lock.unlock()

        let deadline = ProcessInfo.processInfo.systemUptime + Self.correctionGateDeadline
        var iterations = 0
        while true {
            iterations += 1
            lock.lock()
            if capturedEvents.isEmpty {
                isGating = false
                lock.unlock()
                return
            }
            if iterations > Self.correctionGateMaxIterations
                || ProcessInfo.processInfo.systemUptime > deadline {
                // Дедлайн/лимит итераций исчерпан — принудительно закрываем gate и
                // отбрасываем оставшуюся очередь, чтобы не крутить цикл на MainActor
                // неограниченно (см. code review B2).
                let dropped = capturedEvents.count
                capturedEvents.removeAll(keepingCapacity: true)
                isGating = false
                lock.unlock()
                notifyGateForceClosed(dropped: dropped)
                return
            }
            let batch = capturedEvents
            capturedEvents.removeAll(keepingCapacity: true)
            lock.unlock()
            replay(batch)
        }
    }

    /// Вызывается watchdog-таймером, не из основного пути коррекции. Закрывает gate,
    /// только если он всё ещё открыт — штатное завершение через finishCorrectionGate()
    /// уже отменяет таймер, так что двойного срабатывания быть не должно.
    private func forceCloseGateIfNeeded() {
        // R4: это тело самого watchdogWorkItem — обнуляем ссылку на себя тем же захватом
        // лока, что и isGating/capturedEvents, не вызывая cancel() на самом себе (уже
        // выполняется, cancel() тут не нужен и не мог бы ничего изменить).
        //
        // B11: cancel() не прерывает уже начавшее исполняться тело work item — он лишь
        // выставляет флаг отмены. Гонка: этот блок мог быть дочерпан из очереди и
        // заблокирован на lock.lock() ДО того, как finishCorrectionGate()/stop() успели
        // обнулить watchdogWorkItem под тем же локом. К моменту, когда этот блок наконец
        // получает лок, штатное завершение уже произошло, а isGating ещё не сброшен
        // (finishCorrectionGate() делает это позже, после replay). Проверка одного isGating
        // тут недостаточна — нужно также убедиться, что watchdogWorkItem всё ещё указывает
        // на ЭТОТ work item: finishCorrectionGate() и stop() обнуляют его под тем же локом,
        // так что watchdog, получивший лок после них, обязан выйти без действий.
        lock.lock()
        guard isGating, watchdogWorkItem != nil else { lock.unlock(); return }
        let dropped = capturedEvents.count
        capturedEvents.removeAll(keepingCapacity: true)
        isGating = false
        watchdogWorkItem = nil
        lock.unlock()
        notifyGateForceClosed(dropped: dropped)
    }

    private func notifyGateForceClosed(dropped: Int) {
        DispatchQueue.main.async { [weak self] in self?.onGateForceClosed?(dropped) }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        lock.lock()
        let disableReason = disablePolicy.notification(for: type)
        lock.unlock()
        if let disableReason {
            // Never re-enable from the event-tap callback. If TCC access was
            // revoked, doing so creates an unbounded disable/enable loop.
            DispatchQueue.main.async { [weak self] in self?.onTapDisabled?(disableReason) }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == typeSteadyEventMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let repeatValue = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        lock.lock()
        if isGating && (type == .keyDown || type == .keyUp || type == .flagsChanged) {
            capturedEvents.append(CapturedInputEvent(type: type, keyCode: keyCode, flags: event.flags, isRepeat: repeatValue))
            lock.unlock()
            return nil
        }
        lock.unlock()

        guard type == .keyDown || type == .flagsChanged ||
                type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown else {
            return Unmanaged.passUnretained(event)
        }

        let snapshot = InputEventSnapshot(
            type: type,
            keyCode: keyCode,
            flags: event.flags,
            isRepeat: repeatValue,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        DispatchQueue.main.async { [weak self] in self?.onEvent?(snapshot) }
        return Unmanaged.passUnretained(event)
    }

    private func runEventLoop(_ eventTap: CFMachPort) {
        autoreleasepool {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            let currentRunLoop = CFRunLoopGetCurrent()
            lock.lock()
            runLoop = currentRunLoop
            runLoopSource = source
            lock.unlock()

            CFRunLoopAddSource(currentRunLoop, source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            CFRunLoopRun()
            CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)

            lock.lock()
            runLoop = nil
            runLoopSource = nil
            lock.unlock()
        }
    }
}

private func typeSteadyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<InputEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return service.handle(type: type, event: event)
}
