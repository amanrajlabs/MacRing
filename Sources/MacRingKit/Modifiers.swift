import AppKit
import Carbon.HIToolbox

/// Conversions between config modifier names ("command", "option", "control",
/// "shift") and AppKit / Carbon flag values.
public enum Modifiers {
    public static let allNames = ["command", "option", "control", "shift"]

    public static func nsFlags(_ names: [String]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for name in names {
            switch name {
            case "command": flags.insert(.command)
            case "option": flags.insert(.option)
            case "control": flags.insert(.control)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
        return flags
    }

    public static func carbonFlags(_ names: [String]) -> UInt32 {
        var flags: UInt32 = 0
        for name in names {
            switch name {
            case "command": flags |= UInt32(cmdKey)
            case "option": flags |= UInt32(optionKey)
            case "control": flags |= UInt32(controlKey)
            case "shift": flags |= UInt32(shiftKey)
            default: break
            }
        }
        return flags
    }

    public static func symbolString(_ names: [String]) -> String {
        var s = ""
        if names.contains("control") { s += "⌃" }
        if names.contains("option") { s += "⌥" }
        if names.contains("shift") { s += "⇧" }
        if names.contains("command") { s += "⌘" }
        return s
    }
}
