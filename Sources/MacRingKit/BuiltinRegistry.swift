import AppKit

/// Future home of built-in mini-tools (timer, color picker, …). v2 ships it
/// empty; `builtin` actions with no registered handler log and beep.
@MainActor
public final class BuiltinRegistry {
    public static let shared = BuiltinRegistry()
    private var handlers: [String: () -> Void] = [:]

    public func register(id: String, handler: @escaping () -> Void) {
        handlers[id] = handler
    }

    public func run(_ id: String) {
        guard let handler = handlers[id] else {
            NSLog("MacRing: no builtin registered for '\(id)'")
            NSSound.beep()
            return
        }
        handler()
    }
}
