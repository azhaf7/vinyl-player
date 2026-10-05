import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts that work even when the player is hidden:
/// ⌃⌥Space play/pause, ⌃⌥→ next, ⌃⌥← previous, ⌃⌥L like.
/// Carbon hot keys don't need Accessibility permission.
final class HotKeys {
    static let shared = HotKeys()

    struct Shortcut {
        let id: UInt32
        let keyCode: Int
        let label: String
    }

    static let shortcuts = [
        Shortcut(id: 1, keyCode: kVK_Space, label: "⌃⌥Space  Play / pause"),
        Shortcut(id: 2, keyCode: kVK_RightArrow, label: "⌃⌥→  Next song"),
        Shortcut(id: 3, keyCode: kVK_LeftArrow, label: "⌃⌥←  Previous song"),
        Shortcut(id: 4, keyCode: kVK_ANSI_L, label: "⌃⌥L  Like the song"),
    ]

    var onPress: ((UInt32) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func setEnabled(_ on: Bool) {
        unregister()
        guard on else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                let id = hk.id
                DispatchQueue.main.async { HotKeys.shared.onPress?(id) }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        for s in Self.shortcuts {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(s.keyCode), UInt32(controlKey | optionKey),
                                             EventHotKeyID(signature: OSType(0x5650_4C59), id: s.id), // "VPLY"
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
        }
    }

    private func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }
}
