import SwiftUI

/// 空会话落地页(Gemini 范式):居中标志 + 大字号问候。
struct EmptyStateView: View {
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(spacing: 30) {
            BrandMark(size: 52, filled: true)

            VStack(spacing: 12) {
                Text(l10n.helloTitle)
                Text(l10n.helloSubtitle)
            }
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    EmptyStateView()
        .frame(width: 800, height: 600)
        .background(Theme.background)
}
