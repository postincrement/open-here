import AppKit
import Carbon
import Foundation

enum ShortcutFormatting {
    static func display(keyCode: Int, modifiersRaw: UInt) -> String {
        guard keyCode >= 0 else { return "Not set" }
        let flags = NSEvent.ModifierFlags(rawValue: modifiersRaw).intersection(.deviceIndependentFlagsMask)
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + keyString(keyCode: UInt16(keyCode), modifiers: flags)
    }

    static func carbonModifiers(from raw: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: raw).intersection(.deviceIndependentFlagsMask)
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    static func isModifierOnly(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }

    private static func keyString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        if let special = specialNames[keyCode] { return special }
        guard let sourceUnmanaged = TISCopyCurrentKeyboardInputSource() else {
            return "Key \(keyCode)"
        }
        let source = sourceUnmanaged.takeRetainedValue()
        guard let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return "Key \(keyCode)"
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let shift = modifiers.contains(.shift) ? UInt32(shiftKey >> 8) & 0xFF : 0
            let error = UCKeyTranslate(
                base,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                shift,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard error == noErr, length > 0 else { return "Key \(keyCode)" }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }

    private static let specialNames: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        76: "Enter",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up"
    ]
}
