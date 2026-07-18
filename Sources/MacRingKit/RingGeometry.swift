import CoreGraphics
import Foundation

/// Pure ring math in y-down (SwiftUI view) coordinates.
/// Index 0 sits at the top; indices advance clockwise.
public enum RingGeometry {
    public static let defaultStartAngle: CGFloat = -.pi / 2

    public static func angle(for index: Int, count: Int,
                             startAngle: CGFloat = defaultStartAngle) -> CGFloat {
        startAngle + 2 * .pi * CGFloat(index) / CGFloat(max(count, 1))
    }

    public static func position(index: Int, count: Int, radius: CGFloat, center: CGPoint,
                                startAngle: CGFloat = defaultStartAngle) -> CGPoint {
        let a = angle(for: index, count: count, startAngle: startAngle)
        return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    }

    /// Nearest item by angle, or nil inside the dead zone (or for an empty ring).
    /// Selection is purely angular so a small flick past the dead zone is enough.
    public static func hitIndex(center: CGPoint, point: CGPoint, count: Int,
                                deadZone: CGFloat,
                                startAngle: CGFloat = defaultStartAngle) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        guard (dx * dx + dy * dy).squareRoot() >= deadZone else { return nil }
        let theta = atan2(dy, dx)
        let step = 2 * .pi / CGFloat(count)
        var rel = (theta - startAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if rel < 0 { rel += 2 * .pi }
        return Int((rel / step).rounded()) % count
    }
}
