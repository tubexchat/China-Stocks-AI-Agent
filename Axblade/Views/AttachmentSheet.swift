import SwiftUI

/// “+” → 附加个股行情:输入代码 → 查询 → 预览 → 附加。
struct AttachmentSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let onDone: () -> Void

    @State private var symbol = ""
    @State private var isLoading = false
    @State private var preview: MarketSnapshot?
    @State private var errorText: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.text.attachSheetTitle)
                .font(.headline)
                .foregroundStyle(Theme.text)

            HStack(spacing: 8) {
                TextField(viewModel.text.aShareSymbolHint, text: $symbol)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(query)
                Button(viewModel.text.query, action: query)
                    .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.text.fetchingQuote).font(.callout).foregroundStyle(Theme.muted)
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let preview {
                SnapshotPreviewCard(snapshot: preview)
            }

            HStack {
                Spacer()
                Button(viewModel.text.cancel, action: onDone)
                Button(viewModel.text.attach) {
                    if let preview { viewModel.attach(preview) }
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.background)
        .onAppear { focused = true }
    }

    private func query() {
        let text = symbol.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isLoading else { return }
        isLoading = true
        errorText = nil
        preview = nil

        Task { @MainActor in
            do {
                preview = try await viewModel.fetchSnapshot(symbol: text)
            } catch {
                errorText = viewModel.text.describe(error)
            }
            isLoading = false
        }
    }
}

/// 行情预览卡。
struct SnapshotPreviewCard: View {
    let snapshot: MarketSnapshot

    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.name.map { "\(snapshot.symbol) · \($0)" } ?? snapshot.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
                Text("A股")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(MarketSnapshot.formatNumber(snapshot.price) + (snapshot.currency.map { " \($0)" } ?? ""))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                if let change = snapshot.changePercent {
                    Text(MarketSnapshot.formatPercent(change))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.changeColor(change))
                }
            }

            if let high = snapshot.high, let low = snapshot.low {
                Text(String(format: l10n.highLowFormat, MarketSnapshot.formatNumber(high), MarketSnapshot.formatNumber(low)))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            if !snapshot.closes.isEmpty {
                SparkLine(values: snapshot.closes)
                    .frame(height: 36)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// 迷你折线。
struct SparkLine: View {
    let values: [Double]
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            if let min = values.min(), let max = values.max(), values.count > 1 {
                let range = max - min == 0 ? 1 : max - min
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((value - min) / range))
                        index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
