import SwiftUI

@main
struct AxbladeApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
                .environment(\.l10n, viewModel.text)
        }
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(viewModel.text.newChatMenu) { viewModel.newConversation() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView(viewModel: viewModel)
                .environment(\.l10n, viewModel.text)
        }
    }
}

private struct RootView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 340)
        } detail: {
            switch viewModel.workspace {
            case .home:
                ChatView(viewModel: viewModel)
            case .tools:
                ToolsView(viewModel: viewModel)
                    .navigationTitle(viewModel.text.quantToolsHeader)
            }
        }
        .background(Theme.background)
    }
}
