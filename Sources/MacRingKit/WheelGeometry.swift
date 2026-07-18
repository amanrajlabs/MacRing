import CoreGraphics
import Foundation

/// Radial layout of the two-band wheel, derived from appearance settings.
/// All values in points; y-down coordinates.
public struct WheelLayout: Equatable {
    public var center: CGPoint
    public var holeRadius: CGFloat
    public var innerOuterRadius: CGFloat
    public var gap: CGFloat
    public var outerBandWidth: CGFloat

    public init(center: CGPoint, appearanceRadius: CGFloat, iconSize: CGFloat) {
        self.center = center
        holeRadius = appearanceRadius * 0.40
        innerOuterRadius = appearanceRadius
        gap = 5
        outerBandWidth = max(iconSize + 34, appearanceRadius * 0.52)
    }

    public var outerInnerRadius: CGFloat { innerOuterRadius + gap }
    public var outerOuterRadius: CGFloat { outerInnerRadius + outerBandWidth }
    public var innerMidRadius: CGFloat { (holeRadius + innerOuterRadius) / 2 }
    public var outerMidRadius: CGFloat { (outerInnerRadius + outerOuterRadius) / 2 }
}

public enum WheelRegion: Equatable {
    case hub, innerBand, gap, outerBand, outside
}

/// Pure wheel math. Angles are radians, y-down, increasing clockwise;
/// category 0 is centered at the top (-π/2). Category wedges divide the full
/// circle equally; child wedges fan out on an arc centered on their category.
public enum WheelGeometry {
    public static func region(of point: CGPoint, in layout: WheelLayout) -> WheelRegion {
        let d = hypot(point.x - layout.center.x, point.y - layout.center.y)
        if d < layout.holeRadius { return .hub }
        if d < layout.innerOuterRadius { return .innerBand }
        if d < layout.outerInnerRadius { return .gap }
        if d < layout.outerOuterRadius { return .outerBand }
        return .outside
    }

    public static func angle(of point: CGPoint, around center: CGPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x)
    }

    public static func categoryMidAngle(_ index: Int, count: Int) -> CGFloat {
        -.pi / 2 + 2 * .pi * CGFloat(index) / CGFloat(max(count, 1))
    }

    public static func categoryIndex(atAngle theta: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let step = 2 * .pi / CGFloat(count)
        var rel = (theta + .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
        if rel < 0 { rel += 2 * .pi }
        return Int((rel / step).rounded()) % count
    }

    public struct Arc: Equatable {
        public var start: CGFloat
        public var step: CGFloat
        public var count: Int

        public init(start: CGFloat, step: CGFloat, count: Int) {
            self.start = start
            self.step = step
            self.count = count
        }

        public var end: CGFloat { start + step * CGFloat(count) }

        public func midAngle(_ index: Int) -> CGFloat {
            start + step * (CGFloat(index) + 0.5)
        }
    }

    /// Each child wedge subtends ~`arcLength` points at the outer band's mid
    /// radius, capped so the whole arc never exceeds a full circle.
    public static func childArc(categoryIndex: Int, categoryCount: Int, childCount: Int,
                                layout: WheelLayout, arcLength: CGFloat = 78) -> Arc {
        let per = min(arcLength / layout.outerMidRadius,
                      2 * .pi / CGFloat(max(childCount, 1)))
        let mid = categoryMidAngle(categoryIndex, count: categoryCount)
        return Arc(start: mid - per * CGFloat(childCount) / 2, step: per, count: childCount)
    }

    public static func childIndex(atAngle theta: CGFloat, arc: Arc) -> Int? {
        guard arc.count > 0, arc.step > 0 else { return nil }
        var rel = (theta - arc.start).truncatingRemainder(dividingBy: 2 * .pi)
        if rel < 0 { rel += 2 * .pi }
        guard rel < arc.step * CGFloat(arc.count) else { return nil }
        return min(Int(rel / arc.step), arc.count - 1)
    }
}
