import AppKit
import MacRingKit
import SwiftUI

/// State for one wheel session. The open category owns the fanned outer arc;
/// hover state is derived from the cursor's radial region and angle.
/// Coordinates are y-down view coordinates of the panel.
@MainActor
final class WheelViewModel: ObservableObject {
    @Published var categories: [RingCategory] = []
    @Published var openCategoryIndex: Int?
    @Published var hoveredChildIndex: Int?
    /// Category wedge directly under the cursor (inner band only). The OPEN
    /// category persists while the cursor is on the child arc; this does not.
    @Published var hoveredCategoryIndex: Int?
    @Published var appearance = AppearanceConfig()
    @Published var center = CGPoint.zero

    var layout: WheelLayout {
        WheelLayout(center: center, appearanceRadius: appearance.ringRadius,
                    iconSize: appearance.iconSize)
    }

    var openCategory: RingCategory? {
        guard let openCategoryIndex, categories.indices.contains(openCategoryIndex) else { return nil }
        return categories[openCategoryIndex]
    }

    var hoveredChild: RingItem? {
        guard let openCategory, let hoveredChildIndex,
              openCategory.items.indices.contains(hoveredChildIndex) else { return nil }
        return openCategory.items[hoveredChildIndex]
    }

    var childArc: WheelGeometry.Arc? {
        guard let openCategoryIndex, categories.indices.contains(openCategoryIndex) else { return nil }
        return WheelGeometry.childArc(categoryIndex: openCategoryIndex,
                                      categoryCount: categories.count,
                                      childCount: categories[openCategoryIndex].items.count,
                                      layout: layout)
    }

    func reset(categories: [RingCategory], appearance: AppearanceConfig, center: CGPoint) {
        self.categories = categories
        self.appearance = appearance
        self.center = center
        openCategoryIndex = nil
        hoveredChildIndex = nil
        hoveredCategoryIndex = nil
    }

    func update(cursor: CGPoint) {
        switch WheelGeometry.region(of: cursor, in: layout) {
        case .innerBand:
            let theta = WheelGeometry.angle(of: cursor, around: center)
            if let idx = WheelGeometry.categoryIndex(atAngle: theta, count: categories.count) {
                hoveredCategoryIndex = idx
                if idx != openCategoryIndex { openCategoryIndex = idx }
            }
            hoveredChildIndex = nil
        case .outerBand, .outside:
            // Outside stays angular so a fast flick past the band still selects.
            hoveredCategoryIndex = nil
            guard let arc = childArc else { return }
            hoveredChildIndex = WheelGeometry.childIndex(
                atAngle: WheelGeometry.angle(of: cursor, around: center), arc: arc)
        case .hub, .gap:
            hoveredCategoryIndex = nil
            hoveredChildIndex = nil
        }
    }

    func openCategory(at index: Int) {
        guard categories.indices.contains(index) else { return }
        openCategoryIndex = index
        hoveredChildIndex = nil
        hoveredCategoryIndex = nil
    }
}
