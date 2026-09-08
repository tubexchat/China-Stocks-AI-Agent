import SwiftUI

@main
struct AxbladeApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
                .frame(minWidth: 960, minHeight: 640)
                .environment(\.l10n, viewModel.text)
        }
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(viewModel.text.newChatMenu) { viewModel.newConversation() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu(viewModel.text.workspaceModules) {
                ForEach(Array(AgentModule.allCases.enumerated()), id: \.element) { index, module in
                    Button(viewModel.text.moduleName(module)) { viewModel.openModule(module) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView(viewModel: viewModel)
                .environment(\.l10n, viewModel.text)
        }
    }
}

struct RootView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 340)
        } detail: {
            switch viewModel.workspace {
            case .chat:
                ChatView(viewModel: viewModel)
            case .modules:
                ModulesView(viewModel: viewModel)
                    .navigationTitle(viewModel.selectedModule.map { viewModel.text.moduleName($0) } ?? viewModel.text.modulesHeader)
            }
        }
        .background(Theme.background)
    }
}
