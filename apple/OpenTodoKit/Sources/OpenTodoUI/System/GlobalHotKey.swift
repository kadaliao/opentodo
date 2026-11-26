// A system-wide keyboard shortcut through Carbon's `RegisterEventHotKey`:
// it works in the sandbox and needs no accessibility permission (it only
// hears its own combination, unlike an event tap). Fails (nil) when
// another app already has the combination.

#if os(macOS)
import Carbon.HIToolbox
import OpenTodoSystem

@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// 'OTqa'
    private static let signature: OSType = 0x4F54_7161

    init?(_ key: HotKey, action: @escaping @MainActor () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, me, &handlerRef)
        guard installed == noErr else { return nil }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(key.keyCode, key.carbonModifiers, id, GetApplicationEventTarget(),
                                         OptionBits(0), &hotKeyRef)
        guard status == noErr else {
            invalidate()
            return nil
        }
    }

    /// Unregisters; call before letting it go.
    func invalidate() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
#endif
