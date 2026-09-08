import SwiftUI

/// 空会话落地页:标志 + 问候 + 四个示例问题(点一下直接发出)。
struct EmptyStateView: View {
    @Environment(\.l10n) private var l10n
    var onSuggestion: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 26) {
            BrandMark(size: 56, filled: true)

            VStack(spacing: 10) {
                Text(l10n.helloTitle)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(l10n.helloSubtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                suggestion(l10n.suggestionLimitUp, icon: "waveform.path.ecg")
                suggestion(l10n.suggestionDragonTiger, icon: "point.3.connected.trianglepath.dotted")
                suggestion(l10n.suggestionHeat, icon: "dot.radiowaves.left.and.right")
                suggestion(l10n.suggestionStock, icon: "chart.xyaxis.line")
            }
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func suggestion(_ text: String, icon: String) -> some View {
        Button {
            onSuggestion?(text)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.accentStrong)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    EmptyStateView()
        .frame(width: 800, height: 600)
        .background(Theme.background)
}
