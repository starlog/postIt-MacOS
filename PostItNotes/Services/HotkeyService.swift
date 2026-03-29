import Foundation
import Carbon
import AppKit

class HotkeyService {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var hotkeyPressed: (() -> Void)?

    private static let hotkeyID = EventHotKeyID(signature: OSType(0x504E_4854), id: 1) // "PNHT"

    func register(modifiers: UInt32, keyCode: UInt32) {
        unregister()

        var hotKeyID = HotkeyService.hotkeyID
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                service.hotkeyPressed?()
            }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPtr, &eventHandler)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    /// Convert Carbon modifier flags to display string
    static func modifierString(from carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }  // Control
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }   // Option
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }    // Shift
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }       // Command
        return parts.joined()
    }

    /// Convert Carbon key code to key name
    static func keyName(from keyCode: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            49: "Space", 50: "`",
            // Function keys
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15",
            118: "F4", 120: "F2", 122: "F1",
            // Special
            36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
            76: "Enter", 115: "Home", 116: "PageUp", 117: "ForwardDelete",
            119: "End", 121: "PageDown",
            123: "Left", 124: "Right", 125: "Down", 126: "Up"
        ]
        return keyMap[keyCode] ?? "Key(\(keyCode))"
    }

    static func hotkeyDisplayString(modifiers: UInt32, keyCode: UInt32) -> String {
        return modifierString(from: modifiers) + keyName(from: keyCode)
    }

    deinit {
        unregister()
    }
}
