import SwiftUI

/// A股智能体标志:圆角方块里一根红色阳线 + 一根绿色阴线(红涨绿跌)。
struct BrandMark: View {
    var size: CGFloat = 28
    var filled = false

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let radius = canvasSize.width * 0.22
            let frame = Path(roundedRect: rect.insetBy(dx: canvasSize.width * 0.06, dy: canvasSize.height * 0.06), cornerRadius: radius)
            if filled {
                context.fill(frame, with: .color(Theme.accent.opacity(0.16)))
            }
            context.stroke(frame, with: .color(Theme.accent), lineWidth: max(1, canvasSize.width * 0.06))

            let w = canvasSize.width, h = canvasSize.height
            // 阳线(红)
            context.fill(Self.candle(x: w * 0.36, top: h * 0.30, bottom: h * 0.66, wickTop: h * 0.20, wickBottom: h * 0.76, width: w * 0.14), with: .color(Theme.up))
            // 阴线(绿)
            context.fill(Self.candle(x: w * 0.64, top: h * 0.42, bottom: h * 0.62, wickTop: h * 0.34, wickBottom: h * 0.72, width: w * 0.14), with: .color(Theme.down))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("A股智能体")
    }

    private static func candle(x: CGFloat, top: CGFloat, bottom: CGFloat, wickTop: CGFloat, wickBottom: CGFloat, width: CGFloat) -> Path {
        var path = Path()
        path.addRect(CGRect(x: x - width / 2, y: top, width: width, height: bottom - top))
        path.addRect(CGRect(x: x - width * 0.12, y: wickTop, width: width * 0.24, height: wickBottom - wickTop))
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
