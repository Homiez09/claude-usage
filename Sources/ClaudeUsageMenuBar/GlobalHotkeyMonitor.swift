import AppKit
import Carbon.HIToolbox

// MARK: - Global C-compatible callback (no closure capture required)
private func hotkeyEventCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    Task { @MainActor in
        GlobalHotkeyMonitor.shared.fireAction()
    }
    return noErr
}

// MARK: - Monitor

/// Registers a system-wide keyboard shortcut using Carbon's RegisterEventHotKey API.
/// This does NOT require Accessibility permissions.
@MainActor
final class GlobalHotkeyMonitor {
    static let shared = GlobalHotkeyMonitor()

    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    // Stored values
    private(set) var keyCode: Int
    private(set) var carbonModifiers: UInt32

    // Default: ⌃⌥C — Control+Option+C (very rarely used by other apps)
    static let defaultKeyCode    = Int(kVK_ANSI_C)
    static let defaultModifiers  = UInt32(controlKey | optionKey)

    private init() {
        let storedKey  = UserDefaults.standard.object(forKey: "HotkeyKeyCode") as? Int
        let storedMods = UserDefaults.standard.object(forKey: "HotkeyCarbonModifiers") as? Int
        keyCode         = storedKey  ?? Self.defaultKeyCode
        carbonModifiers = storedMods != nil ? UInt32(storedMods!) : Self.defaultModifiers
    }

    // MARK: Registration

    func register() {
        unregister()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.fourCC("CLUD")
        hotKeyID.id        = 1

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )

        // Install application event handler on the event dispatcher target
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyEventCallback,
            1,
            &eventSpec,
            nil,
            &handlerRef
        )

        RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef  { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = handlerRef { RemoveEventHandler(ref);    handlerRef = nil }
    }

    func update(keyCode newKey: Int, carbonModifiers newMods: UInt32) {
        keyCode         = newKey
        carbonModifiers = newMods
        UserDefaults.standard.set(newKey,      forKey: "HotkeyKeyCode")
        UserDefaults.standard.set(Int(newMods), forKey: "HotkeyCarbonModifiers")
        register()
    }

    func resetToDefault() {
        update(keyCode: Self.defaultKeyCode, carbonModifiers: Self.defaultModifiers)
    }

    // Called by the global C callback
    func fireAction() {
        onActivate?()
    }

    // MARK: Display

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += Self.keyCodeToString(keyCode)
        return s
    }

    // MARK: Helpers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    // swiftlint:disable cyclomatic_complexity
    static func keyCodeToString(_ code: Int) -> String {
        switch code {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space:  return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab:    return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_F1:     return "F1"
        case kVK_F2:     return "F2"
        case kVK_F3:     return "F3"
        case kVK_F4:     return "F4"
        case kVK_F5:     return "F5"
        case kVK_F6:     return "F6"
        case kVK_F7:     return "F7"
        case kVK_F8:     return "F8"
        case kVK_F9:     return "F9"
        case kVK_F10:    return "F10"
        case kVK_F11:    return "F11"
        case kVK_F12:    return "F12"
        default:         return "?"
        }
    }
    // swiftlint:enable cyclomatic_complexity

    private static func fourCC(_ s: String) -> FourCharCode {
        s.unicodeScalars.reduce(0) { ($0 << 8) + FourCharCode($1.value) }
    }
}
