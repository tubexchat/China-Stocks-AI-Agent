import SwiftUI
import AppKit

/// Axblade 配色:Binance Dark/Light。
/// 唯一来源是 `ChillSkill-Website/design-tokens.json`,Web 与 Mac 逐值镜像;
/// `ThemeTokenTests` 会断言下面这张表,漏改一边就当场红。
enum Theme {
    /// 语义 token → (深色, 浅色) 的 sRGB 十六进制。视图不直接写 hex,一律走语义色。
    static let tokens: [String: (dark: UInt32, light: UInt32)] = [
        "background": (dark: 0x0B0E11, light: 0xFFFFFF),
        "surface": (dark: 0x181A20, light: 0xFAFAFA),
        "surface2": (dark: 0x1E2329, light: 0xF5F5F5),
        "elevated": (dark: 0x2B3139, light: 0xEAECEF),
        "border": (dark: 0x2B3139, light: 0xEAECEF),
        "text": (dark: 0xEAECEF, light: 0x1E2329),
        "muted": (dark: 0x848E9C, light: 0x707A8A),
        "disabled": (dark: 0x5E6673, light: 0xB7BDC6),
        "accent": (dark: 0xFCD535, light: 0xFCD535),
        "accentStrong": (dark: 0xF0B90B, light: 0xF0B90B),
        "onAccent": (dark: 0x181A20, light: 0x181A20),
        "up": (dark: 0x0ECB81, light: 0x0ECB81),
        "down": (dark: 0xF6465D, light: 0xF6465D)
    ]

    /// 页面 / 主区底
    static let background = token("background")
    /// 侧栏 —— 与卡片同一张纸
    static let sidebar = token("surface")
    /// 卡片
    static let surface = token("surface")
    /// 输入卡、悬停、代码块
    static let surface2 = token("surface2")
    /// 选中、强分隔
    static let elevated = token("elevated")
    static let border = token("border")
    static let text = token("text")
    static let muted = token("muted")
    /// 禁用态文字/描边
    static let disabled = token("disabled")
    /// 品牌主色(币安黄)
    static let accent = token("accent")
    /// 悬停 / 强调
    static let accentStrong = token("accentStrong")
    /// 黄底上的字
    static let onAccent = token("onAccent")
    /// 涨 / 成功
    static let up = token("up")
    /// 跌 / 错误
    static let down = token("down")
    /// 黄色底纹:深色 12%、浅色 16% 的 accent
    static let accentSoft = alpha("accent", dark: 0.12, light: 0.16)

    static func hexColor(_ hex: UInt32) -> Color {
        Color(nsColor: nsColor(hex))
    }

    /// 随系统外观切换的动态色。
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(isDark(appearance) ? dark : light)
        })
    }

    /// 按名字取 token;拼错立刻崩,`ThemeTokenTests` 会抓到。
    private static func token(_ name: String) -> Color {
        guard let pair = tokens[name] else { preconditionFailure("未知设计 token:\(name)") }
        return dynamic(light: pair.light, dark: pair.dark)
    }

    /// 半透明底纹:两种外观下透明度不同。
    private static func alpha(_ name: String, dark darkAlpha: CGFloat, light lightAlpha: CGFloat) -> Color {
        guard let pair = tokens[name] else { preconditionFailure("未知设计 token:\(name)") }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = isDark(appearance)
            return nsColor(isDark ? pair.dark : pair.light)
                .withAlphaComponent(isDark ? darkAlpha : lightAlpha)
        })
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
