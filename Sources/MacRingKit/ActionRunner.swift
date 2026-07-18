import AppKit
import Foundation

@MainActor
public enum ActionRunner {
    public static func run(_ item: RingItem) {
        switch item.action {
        case .app(let value):
            guard let url = resolveAppURL(value) else { return fail("app not found: \(value)") }
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                if let error { NSLog("MacRing: open app failed: \(error)") }
            }
        case .url(let value):
            guard let url = URL(string: value) else { return fail("bad URL: \(value)") }
            NSWorkspace.shared.open(url)
        case .file(let value):
            let path = (value as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                return fail("no such file: \(path)")
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .shell(let command):
            launch("/bin/zsh", ["-lc", command])
        case .shortcut(let name):
            launch("/usr/bin/shortcuts", ["run", name])
        case .submenu:
            break // handled by the ring UI, never executed directly
        }
    }

    /// Accepts an absolute/tilde path, a bundle identifier, or a bare app name
    /// searched in the standard application folders.
    nonisolated public static func resolveAppURL(_ value: String) -> URL? {
        if value.hasPrefix("/") || value.hasPrefix("~") {
            let path = (value as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if value.contains("."),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) {
            return url
        }
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities"] {
            let path = "\(dir)/\(value).app"
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    private static func launch(_ tool: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        do { try p.run() } catch { fail("\(tool) failed: \(error)") }
    }

    private static func fail(_ message: String) {
        NSLog("MacRing: \(message)")
        NSSound.beep()
    }
}
