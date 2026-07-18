import Foundation

public struct InstalledApp: Identifiable, Equatable, Sendable {
    public let name: String
    public let path: String
    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// Shallow scan of the standard application folders (one subfolder level in
/// /Applications for vendor directories). Cheap enough to run on demand.
public enum AppScanner {
    public static func scan() -> [InstalledApp] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var found: [String: InstalledApp] = [:]
        collect(in: "/Applications", depth: 1, into: &found)
        collect(in: "/System/Applications", depth: 0, into: &found)
        collect(in: "/System/Applications/Utilities", depth: 0, into: &found)
        collect(in: home + "/Applications", depth: 0, into: &found)
        return found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func collect(in dir: String, depth: Int,
                                into found: inout [String: InstalledApp]) {
        let fm = FileManager.default
        for entry in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
            let path = dir + "/" + entry
            if entry.hasSuffix(".app") {
                found[path] = InstalledApp(name: String(entry.dropLast(4)), path: path)
            } else if depth > 0, !entry.hasPrefix(".") {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    collect(in: path, depth: depth - 1, into: &found)
                }
            }
        }
    }
}
