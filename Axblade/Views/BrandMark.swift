import SwiftUI

/// Axblade 标志:青色六边形里一道斜切的刀锋。
struct BrandMark: View {
    var size: CGFloat = 28
    var filled = false

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let hexagon = Self.hexagon(in: rect)
            let blade = Self.blade(in: rect)

            if filled {
                context.fill(hexagon, with: .color(Theme.accent.opacity(0.16)))
            }
            context.stroke(
                hexagon,
                with: .color(Theme.accent),
                style: StrokeStyle(lineWidth: max(1, canvasSize.width * 0.06), lineJoin: .round)
            )
            context.fill(blade, with: .color(Theme.accent))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("ChillSkill")
    }

    private static func hexagon(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.88
        var path = Path()
        for corner in 0..<6 {
            let angle = CGFloat(corner) / 6 * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            corner == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private static func blade(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: width * 0.34, y: height * 0.70))
        path.addLine(to: CGPoint(x: width * 0.60, y: height * 0.26))
        path.addLine(to: CGPoint(x: width * 0.70, y: height * 0.34))
        path.addLine(to: CGPoint(x: width * 0.44, y: height * 0.74))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 16) {
        BrandMark(size: 24)
        BrandMark(size: 48, filled: true)
    }
    .padding()
    .background(Theme.background)
}
