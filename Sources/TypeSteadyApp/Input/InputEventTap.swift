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

final class InputEventTap: @unchecked Sendable {
    var onEvent: ((InputEventSnapshot) -> Void)?
    var onTapDisabled: (() -> Void)?

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var isGating = false
    private var capturedEvents: [CapturedInputEvent] = []

    @discardableResult
    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard tap == nil else { return true }

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
        let worker = Thread { [weak self] in self?.runEventLoop(eventTap) }
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
        lock.unlock()

        if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: false) }
        if let currentRunLoop { CFRunLoopStop(currentRunLoop) }
    }

    func beginCorrectionGate() {
        lock.lock()
        capturedEvents.removeAll(keepingCapacity: true)
        isGating = true
        lock.unlock()
    }

    func finishCorrectionGate(replay: ([CapturedInputEvent]) -> Void) {
        while true {
            lock.lock()
            if capturedEvents.isEmpty {
                isGating = false
                lock.unlock()
                return
            }
            let batch = capturedEvents
            capturedEvents.removeAll(keepingCapacity: true)
            lock.unlock()
            replay(batch)
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let currentTap = tap
            lock.unlock()
            if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
            DispatchQueue.main.async { [weak self] in self?.onTapDisabled?() }
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

        guard type == .keyDown || type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown else {
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
