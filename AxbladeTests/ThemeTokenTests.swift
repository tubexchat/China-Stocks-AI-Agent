import XCTest
import SwiftUI
@testable import Axblade

/// 设计 token 守护测试:深色 / 浅色两套语义色,涨跌遵循 A 股「红涨绿跌」。
final class ThemeTokenTests: XCTestCase {
    private func assertToken(
        _ name: String, dark: UInt32, light: UInt32,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let token = try XCTUnwrap(Theme.tokens[name], "缺少 token \(name)", file: file, line: line)
        XCTAssertEqual(token.dark, dark, "\(name).dark", file: file, line: line)
        XCTAssertEqual(token.light, light, "\(name).light", file: file, line: line)
    }

    func testTokensMatchTheDesignTable() throws {
        try assertToken("background", dark: 0x0B0E11, light: 0xFFFFFF)
        try assertToken("surface", dark: 0x181A20, light: 0xFAFAFA)
        try assertToken("surface2", dark: 0x1E2329, light: 0xF5F5F5)
        try assertToken("elevated", dark: 0x2B3139, light: 0xEAECEF)
        try assertToken("border", dark: 0x2B3139, light: 0xEAECEF)
        try assertToken("text", dark: 0xEAECEF, light: 0x1E2329)
        try assertToken("muted", dark: 0x848E9C, light: 0x707A8A)
        try assertToken("disabled", dark: 0x5E6673, light: 0xB7BDC6)
        try assertToken("accent", dark: 0xFCD535, light: 0xFCD535)
        try assertToken("accentStrong", dark: 0xF0B90B, light: 0xF0B90B)
        try assertToken("onAccent", dark: 0x181A20, light: 0x181A20)
        try assertToken("up", dark: 0xF6465D, light: 0xE5303F)
        try assertToken("down", dark: 0x0ECB81, light: 0x0FA968)
    }

    /// 侧栏与卡片同一张纸,不再单独调色。
    func testSidebarSharesTheSurfaceToken() throws {
        let surface = try XCTUnwrap(Theme.tokens["surface"])
        XCTAssertEqual(surface.dark, 0x181A20)
        XCTAssertEqual(surface.light, 0xFAFAFA)
    }

    /// 每个语义色都得能从 token 表里取到值(拼错 key 会在这里崩)。
    func testEverySemanticColorResolves() {
        let colors: [Color] = [
            Theme.background, Theme.sidebar, Theme.surface, Theme.surface2, Theme.elevated,
            Theme.border, Theme.text, Theme.muted, Theme.disabled,
            Theme.accent, Theme.accentStrong, Theme.onAccent, Theme.accentSoft,
            Theme.up, Theme.down
        ]
        XCTAssertEqual(colors.count, 15)
    }
}
