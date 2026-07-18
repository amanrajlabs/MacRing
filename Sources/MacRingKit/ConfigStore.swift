import Foundation

/// Loads and saves the JSON config at
/// ~/Library/Application Support/MacRing/config.json.
/// A broken file never nukes the running config: `lastError` is set and the
/// previous (or default) config stays active.
@MainActor
public final class ConfigStore {
    public static let shared = ConfigStore()
    public static let changedNotification = Notification.Name("MacRingConfigChanged")

    public private(set) var config: RingConfig
    public private(set) var lastError: String?
    public let configURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacRing", isDirectory: true)
        configURL = dir.appendingPathComponent("config.json")
        config = RingConfig.defaultConfig()
        if let loaded = Self.read(from: configURL).0 {
            config = loaded
        } else if !FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            Self.write(config, to: configURL)
        } else {
            lastError = Self.read(from: configURL).1
        }
    }

    public func reload() {
        let (loaded, error) = Self.read(from: configURL)
        lastError = error
        if let loaded { config = loaded }
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    public func save(_ newConfig: RingConfig) {
        config = newConfig
        lastError = nil
        Self.write(newConfig, to: configURL)
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    private static func read(from url: URL) -> (RingConfig?, String?) {
        guard let data = try? Data(contentsOf: url) else { return (nil, nil) }
        do {
            return (try JSONDecoder().decode(RingConfig.self, from: data), nil)
        } catch {
            NSLog("MacRing: config parse failed: \(error)")
            return (nil, "\(error)")
        }
    }

    private static func write(_ config: RingConfig, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
