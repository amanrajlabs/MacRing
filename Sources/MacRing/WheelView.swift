import AppKit
import MacRingKit
import SwiftUI

extension Color {
    /// "#RRGGBB" or "RRGGBB"; falls back to orange on garbage.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = .orange
            return
        }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

@MainActor
enum IconProvider {
    /// Real app/file icons when available; otherwise nil and the view falls
    /// back to an SF Symbol.
    static func nsImage(for item: RingItem) -> NSImage? {
        if item.symbol != nil { return nil }
        switch item.action {
        case .app(let value):
            guard let url = ActionRunner.resolveAppURL(value) else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        case .file(let value):
            let path = (value as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return NSWorkspace.shared.icon(forFile: path)
        default:
            return nil
        }
    }

    static func fallbackSymbol(for item: RingItem) -> String {
        if let symbol = item.symbol { return symbol }
        switch item.action {
        case .app: return "app.dashed"
        case .url: return "globe"
        case .file: return "folder"
        case .shell: return "terminal"
        case .shortcut: return "wand.and.stars"
        case .submenu: return "square.grid.3x3"
        case .builtin: return "puzzlepiece.extension"
        }
    }
}

/// Donut sector between two angles (radians, y-down, clockwise-increasing),
/// drawn around the frame's center.
struct WedgeShape: Shape {
    var startAngle: CGFloat
    var endAngle: CGFloat
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: outerRadius,
                 startAngle: .radians(startAngle), endAngle: .radians(endAngle),
                 clockwise: false)
        p.addArc(center: c, radius: innerRadius,
                 startAngle: .radians(endAngle), endAngle: .radians(startAngle),
                 clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// One wedge with its content placed at the band's mid radius. All segments
/// share the parent ZStack's center, so frames just need to be square.
/// `highlighted` = cursor is on this wedge (white). `tinted` = open category
/// whose cursor is elsewhere (accent wash, dark text stays white).
private struct WedgeSegment<Content: View>: View {
    let start: CGFloat
    let end: CGFloat
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let highlighted: Bool
    var tinted: Bool = false
    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        let mid = (start + end) / 2
        let midRadius = (innerRadius + outerRadius) / 2
        ZStack {
            WedgeShape(startAngle: start, endAngle: end,
                       innerRadius: innerRadius, outerRadius: outerRadius)
                .fill(highlighted ? Color.white.opacity(0.92)
                      : tinted ? accent.opacity(0.26)
                      : Color.black.opacity(0.62))
            WedgeShape(startAngle: start, endAngle: end,
                       innerRadius: innerRadius, outerRadius: outerRadius)
                .stroke(highlighted || tinted ? accent : .white.opacity(0.14),
                        lineWidth: tinted && !highlighted ? 1.5 : 1)
            content()
                .offset(x: midRadius * cos(mid), y: midRadius * sin(mid))
        }
        .frame(width: outerRadius * 2, height: outerRadius * 2)
    }
}

struct WheelView: View {
    @ObservedObject var model: WheelViewModel
    var onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(model.appearance.dimOpacity)
            wheel.position(model.center)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var wheel: some View {
        let layout = model.layout
        let accent = Color(hex: model.appearance.accentHex)
        return ZStack {
            categoryWedges(layout: layout, accent: accent)
            childWedges(layout: layout, accent: accent)
            hub(layout: layout)
        }
        .frame(width: layout.outerOuterRadius * 2, height: layout.outerOuterRadius * 2)
    }

    private func categoryWedges(layout: WheelLayout, accent: Color) -> some View {
        let count = max(model.categories.count, 1)
        let halfStep = .pi / CGFloat(count)
        return ForEach(Array(model.categories.enumerated()), id: \.element.id) { i, category in
            let mid = WheelGeometry.categoryMidAngle(i, count: model.categories.count)
            let hovered = i == model.hoveredCategoryIndex
            let open = i == model.openCategoryIndex
            WedgeSegment(start: mid - halfStep, end: mid + halfStep,
                         innerRadius: layout.holeRadius,
                         outerRadius: layout.innerOuterRadius,
                         highlighted: hovered, tinted: open && !hovered,
                         accent: accent) {
                VStack(spacing: 3) {
                    Image(systemName: category.symbol)
                        .font(.system(size: 17, weight: .semibold))
                    Text(category.name)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(hovered ? Color.black : .white)
                .frame(maxWidth: max(layout.innerOuterRadius * 0.55, 60))
            }
        }
    }

    @ViewBuilder
    private func childWedges(layout: WheelLayout, accent: Color) -> some View {
        if let open = model.openCategory, let arc = model.childArc {
            ForEach(Array(open.items.enumerated()), id: \.element.id) { j, item in
                let hovered = j == model.hoveredChildIndex
                WedgeSegment(start: arc.start + arc.step * CGFloat(j),
                             end: arc.start + arc.step * CGFloat(j + 1),
                             innerRadius: layout.outerInnerRadius,
                             outerRadius: layout.outerOuterRadius,
                             highlighted: hovered, accent: accent) {
                    VStack(spacing: 2) {
                        childIcon(item, hovered: hovered)
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(hovered ? Color.black : .white)
                        if j < 9 {
                            Text("\(j + 1)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(hovered ? Color.black.opacity(0.55)
                                                         : .white.opacity(0.55))
                        }
                    }
                    .frame(maxWidth: 84)
                }
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            .animation(.spring(duration: 0.22), value: model.openCategoryIndex)
        }
    }

    @ViewBuilder
    private func childIcon(_ item: RingItem, hovered: Bool) -> some View {
        let side = model.appearance.iconSize * 0.62
        if let nsImage = model.icon(for: item) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
        } else {
            Image(systemName: IconProvider.fallbackSymbol(for: item))
                .font(.system(size: side * 0.62, weight: .medium))
                .foregroundStyle(hovered ? Color.black : .white)
        }
    }

    private func hub(layout: WheelLayout) -> some View {
        VStack(spacing: 2) {
            if let index = model.openCategoryIndex, let category = model.openCategory {
                Text(category.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(index + 1)/\(model.categories.count)")
                    .font(.system(size: 10, design: .rounded))
                    .opacity(0.6)
            } else {
                Text("MacRing")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: layout.holeRadius * 2 - 8, height: layout.holeRadius * 2 - 8)
        .background(Circle().fill(.black.opacity(0.7)))
        .overlay(Circle().strokeBorder(.white.opacity(0.15)))
    }
}
