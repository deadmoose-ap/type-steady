import Carbon
import Foundation

final class GlobalHotkeyManager {
    var onPerformTextAction: (() -> Void)?

    private var handlerRef: EventHandlerRef?
    private var manualRef: EventHotKeyRef?

    func start(choice: HotkeyChoice) {
        stop()
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            typeSteadyHotkeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        let signature: OSType = 0x4C535754
        let manualID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            choice.carbonModifiers,
            manualID,
            GetApplicationEventTarget(),
            0,
            &manualRef
        )

    }

    func stop() {
        if let manualRef { UnregisterEventHotKey(manualRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        manualRef = nil
        handlerRef = nil
    }

    fileprivate func handle(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        guard status == noErr else { return status }
        DispatchQueue.main.async { [weak self] in
            if hotkeyID.id == 1 {
                self?.onPerformTextAction?()
            }
        }
        return noErr
    }
}

private func typeSteadyHotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    return Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue().handle(event)
}
