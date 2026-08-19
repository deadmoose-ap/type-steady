import CoreGraphics
import Foundation

enum EventSynthesizerError: Error {
    case eventSourceUnavailable
    case eventCreationFailed
}

struct EventSynthesizer {
    private static let deleteKeyCode: CGKeyCode = 51
    private static let hijackingModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// B1: было `Thread.sleep` в плотном цикле на MainActor — блокировало UI и run loop
    /// целиком на весь таймаут ожидания. `Task.sleep` отпускает поток между проверками,
    /// run loop продолжает крутиться (окно настроек отвечает, tap-колбэки не копятся).
    func waitForModifierRelease(timeout: TimeInterval = 0.35) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if CGEventSource.flagsState(.hidSystemState).isDisjoint(with: Self.hijackingModifiers) {
                return true
            }
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
        return false
    }

    func sendBackspaces(_ count: Int) async throws {
        guard count > 0 else { return }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventSynthesizerError.eventSourceUnavailable
        }
        for _ in 0..<count {
            try postKey(keyCode: Self.deleteKeyCode, flags: [], source: source)
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func replayPhysicalKeys(_ keys: [PhysicalKey]) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventSynthesizerError.eventSourceUnavailable
        }
        for key in keys {
            var flags: CGEventFlags = []
            if key.shift { flags.insert(.maskShift) }
            if key.capsLock { flags.insert(.maskAlphaShift) }
            try postKey(keyCode: key.keyCode, flags: flags, source: source)
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func injectUnicode(_ source: String) async throws {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            throw EventSynthesizerError.eventSourceUnavailable
        }
        let chunks = Self.chunkUTF16(source, maximumCodeUnits: 20)
        for (index, chunk) in chunks.enumerated() {
            try chunk.withUnsafeBufferPointer { buffer in
                try postUnicode(buffer: buffer, keyDown: true, source: eventSource)
                try postUnicode(buffer: buffer, keyDown: false, source: eventSource)
            }
            if index < chunks.count - 1 { try? await Task.sleep(nanoseconds: 2_000_000) }
        }
    }

    func replayCapturedEvents(_ events: [CapturedInputEvent]) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventSynthesizerError.eventSourceUnavailable
        }
        for captured in events {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: captured.keyCode,
                keyDown: captured.type != .keyUp
            ) else { throw EventSynthesizerError.eventCreationFailed }
            event.type = captured.type
            event.flags = captured.flags
            event.setIntegerValueField(.eventSourceUserData, value: typeSteadyEventMarker)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: captured.isRepeat ? 1 : 0)
            event.post(tap: .cghidEventTap)
        }
    }

    static func chunkUTF16(_ source: String, maximumCodeUnits: Int) -> [[UniChar]] {
        precondition(maximumCodeUnits >= 2)
        guard !source.isEmpty else { return [] }
        var result: [[UniChar]] = []
        var current: [UniChar] = []
        current.reserveCapacity(maximumCodeUnits)

        for scalar in source.unicodeScalars {
            let value = scalar.value
            let required = value <= 0xFFFF ? 1 : 2
            if current.count + required > maximumCodeUnits {
                result.append(current)
                current.removeAll(keepingCapacity: true)
            }
            if value <= 0xFFFF {
                current.append(UniChar(value))
            } else {
                let shifted = value - 0x10000
                current.append(UniChar(0xD800 + (shifted >> 10)))
                current.append(UniChar(0xDC00 + (shifted & 0x3FF)))
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags, source: CGEventSource) throws {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw EventSynthesizerError.eventCreationFailed
        }
        for event in [keyDown, keyUp] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: typeSteadyEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func postUnicode(
        buffer: UnsafeBufferPointer<UniChar>,
        keyDown: Bool,
        source: CGEventSource
    ) throws {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else {
            throw EventSynthesizerError.eventCreationFailed
        }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: typeSteadyEventMarker)
        event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        event.post(tap: .cghidEventTap)
    }
}
