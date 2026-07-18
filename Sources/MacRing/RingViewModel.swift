import AppKit
import MacRingKit
import SwiftUI

/// State for one ring session: item stack (root + drilled submenus), hover,
/// and submenu dwell. Coordinates are y-down view coordinates of the panel.
@MainActor
final class RingViewModel: ObservableObject {
    @Published var stack: [[RingItem]] = []
    @Published var hoveredIndex: Int?
    @Published var appearance = AppearanceConfig()
    @Published var center = CGPoint.zero

    private var hoverStart: Date?

    /// Hovering a submenu this long fans it open.
    static let submenuDwell: TimeInterval = 0.35

    var currentItems: [RingItem] { stack.last ?? [] }
    var inSubmenu: Bool { stack.count > 1 }

    var hoveredItem: RingItem? {
        guard let hoveredIndex, currentItems.indices.contains(hoveredIndex) else { return nil }
        return currentItems[hoveredIndex]
    }

    var deadZone: CGFloat { max(34, appearance.iconSize * 0.75) }

    func reset(items: [RingItem], appearance: AppearanceConfig, center: CGPoint) {
        stack = [items]
        self.appearance = appearance
        self.center = center
        hoveredIndex = nil
        hoverStart = nil
    }

    func update(cursor: CGPoint) {
        let idx = RingGeometry.hitIndex(center: center, point: cursor,
                                        count: currentItems.count, deadZone: deadZone)
        if idx != hoveredIndex {
            hoveredIndex = idx
            hoverStart = idx == nil ? nil : Date()
        } else if let idx, let start = hoverStart,
                  case .submenu(let children) = currentItems[idx].action,
                  Date().timeIntervalSince(start) > Self.submenuDwell {
            push(children)
        }
    }

    func push(_ children: [RingItem]) {
        stack.append(children)
        hoveredIndex = nil
        hoverStart = nil
    }

    /// Pops one submenu level; false when already at the root.
    func pop() -> Bool {
        guard stack.count > 1 else { return false }
        stack.removeLast()
        hoveredIndex = nil
        hoverStart = nil
        return true
    }

    func hover(index: Int) {
        guard currentItems.indices.contains(index) else { return }
        hoveredIndex = index
        hoverStart = Date()
    }
}
