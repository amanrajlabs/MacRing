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

struct RingView: View {
    @ObservedObject var model: RingViewModel
    var onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(model.appearance.dimOpacity)
            let items = model.currentItems
            let accent = Color(hex: model.appearance.accentHex)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                RingIconView(item: item,
                             number: index < 9 ? index + 1 : nil,
                             hovered: index == model.hoveredIndex,
                             size: model.appearance.iconSize,
                             accent: accent)
                    .position(RingGeometry.position(index: index, count: items.count,
                                                    radius: model.appearance.ringRadius,
                                                    center: model.center))
                    .animation(.spring(duration: 0.18), value: model.hoveredIndex)
            }
            centerHub.position(model.center)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var centerHub: some View {
        VStack(spacing: 2) {
            Text(model.hoveredItem?.title
                 ?? (model.inSubmenu ? "esc \u{2039} back" : "MacRing"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.black.opacity(0.65)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
        .fixedSize()
    }
}

private struct RingIconView: View {
    let item: RingItem
    let number: Int?
    let hovered: Bool
    let size: Double
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(.black.opacity(hovered ? 0.85 : 0.6))
                    .overlay(Circle().strokeBorder(
                        hovered ? accent : .white.opacity(0.25),
                        lineWidth: hovered ? 2.5 : 1))
                    .shadow(color: hovered ? accent.opacity(0.6) : .black.opacity(0.4),
                            radius: hovered ? 12 : 5)
                iconImage
            }
            .frame(width: size, height: size)
            if let number {
                Text("\(number)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(3)
                    .background(Circle().fill(.black.opacity(0.7)))
                    .offset(x: 3, y: 3)
            }
        }
        .scaleEffect(hovered ? 1.22 : 1.0)
    }

    @ViewBuilder
    private var iconImage: some View {
        if let nsImage = IconProvider.nsImage(for: item) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.72, height: size * 0.72)
        } else {
            Image(systemName: IconProvider.fallbackSymbol(for: item))
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}
