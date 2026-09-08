import SwiftUI

/// 没有 viewModel 的叶子视图(图表、状态条、报告栏)经环境取文案;
/// 在 App 根部注入 `viewModel.text`,切语言时随 body 重算而更新。
private struct L10nKey: EnvironmentKey {
    static let defaultValue = L10nStrings.zh
}

extension EnvironmentValues {
    var l10n: L10nStrings {
        get { self[L10nKey.self] }
        set { self[L10nKey.self] = newValue }
    }
}
