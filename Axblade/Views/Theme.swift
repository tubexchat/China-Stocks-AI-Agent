import SwiftUI
import AppKit

/// A股智能体配色:深色 / 浅色两套语义 token。
/// 涨跌遵循 A 股习惯 —— **红涨绿跌**;`ThemeTokenTests` 会断言下面这张表。
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
        "up": (dark: 0xF6465D, light: 0xE5303F),
        "down": (dark: 0x0ECB81, light: 0x0FA968)
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
    /// 品牌主色(金黄)
    static let accent = token("accent")
    /// 悬停 / 强调
    static let accentStrong = token("accentStrong")
    /// 黄底上的字
    static let onAccent = token("onAccent")
    /// 涨(A 股:红)
    static let up = token("up")
    /// 跌(A 股:绿)
    static let down = token("down")
    /// 成功提示
    static let success = token("down")
    /// 错误 / 危险
    static let danger = token("up")

    /// 按涨跌幅着色:正红、负绿、零用正文色。
    static func changeColor(_ value: Double?) -> Color {
        guard let value, value != 0 else { return text }
        return value > 0 ? up : down
    }

    /// 0–100 分数着色:≥60 红、<40 绿、其余中性。
    static func scoreColor(_ score: Int, neutral: Color = text) -> Color {
        if score >= 60 { return up }
        if score < 40 { return down }
        return neutral
    }

    /// 均线结构着色:多头红、空头绿、交织灰。
    static func alignmentColor(_ metrics: TrendMetrics) -> Color {
        if metrics.bullishAlignment { return up }
        if metrics.bearishAlignment { return down }
        return muted
    }

    /// 异动标签着色:含「涨」红、含「跌」绿、其余中性。
    static func tagColor(_ tag: String) -> Color {
        if tag.contains("涨") { return up }
        if tag.contains("跌") { return down }
        return muted
    }
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
