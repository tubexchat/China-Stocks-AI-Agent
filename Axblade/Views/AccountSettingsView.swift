import SwiftUI
import AppKit

/// 设置 → 账户。未登录是登录/注册表单,已登录是额度 + 权限 + 设备的仪表盘。
/// 所有错误文案以后端 `error.message` 为准,客户端只负责本地校验。
struct AccountSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn, signUp
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var passwordNotice: String?
    @State private var isChangingPassword = false

    @State private var deletePassword = ""
    @State private var deleteError: String?
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false
    @State private var didCopyCode = false
    @State private var passwordNeedsReauth = false
    @State private var deleteNeedsReauth = false

    private var text: L10nStrings { viewModel.text }

    var body: some View {
        ScrollView {
            // 判定登录态只认令牌:account.json 只是离线展示用的缓存,
            // 两者一旦不同步(钥匙串被换签名清掉等),不能把人卡在没有登录表单的仪表盘上。
            if viewModel.isSignedIn {
                dashboard
            } else if case .userCode(let code, _) = viewModel.authProgress {
                deviceCodePrompt(code)
            } else {
                authForm
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .task {
            guard viewModel.isSignedIn else { return }
            await viewModel.refreshMe()
            await viewModel.refreshSessions()
        }
    }

    // MARK: - 未登录:登录 / 注册

    private var authForm: some View {
        VStack(spacing: 14) {
            BrandMark(size: 44, filled: true)

            Text(text.signInTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text(text.signInSubtitle)
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            // GitHub / Apple 是主入口,邮箱收进下面的折叠区。
            VStack(spacing: 8) {
                Button {
                    viewModel.signInWithGitHub()
                } label: {
                    Label(text.signInGitHub, systemImage: "chevron.left.forwardslash.chevron.right")
                        .frame(width: 240)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button {
                    viewModel.signInWithApple()
                } label: {
                    Label(text.signInApple, systemImage: "apple.logo")
                        .frame(width: 240)
                }
                .controlSize(.large)
            }
            .disabled(viewModel.isAuthBusy)

            if viewModel.isAuthBusy { ProgressView().controlSize(.small) }

            if let error = viewModel.authError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(Theme.down)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            // 后端回 409「该邮箱已用密码注册」时这里会自动展开(见 AppViewModel.report)。
            DisclosureGroup(text.signInWithEmail, isExpanded: $viewModel.isEmailFormExpanded) {
                emailForm
            }
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: 320)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    /// GitHub 设备码:大号用户码 + 复制 + 取消。浏览器已经被 view model 打开了。
    private func deviceCodePrompt(_ code: String) -> some View {
        VStack(spacing: 16) {
            BrandMark(size: 40, filled: true)
            Text(text.deviceCodeTitle)
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text(code)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button(didCopyCode ? text.copied : text.copyCode) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    didCopyCode = true
                }
                ProgressView().controlSize(.small)
            }
            Text(text.deviceCodeHint)
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button(text.cancel) { viewModel.cancelSignIn() }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    /// 次要入口:邮箱登录 / 注册(与 0.3.0 完全一致的表单)。
    private var emailForm: some View {
        VStack(spacing: 12) {
            Picker("", selection: $mode) {
                Text(text.signInButton).tag(Mode.signIn)
                Text(text.signUpButton).tag(Mode.signUp)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)

            VStack(spacing: 8) {
                TextField(text.email, text: $email)
                    .textContentType(.username)
                if mode == .signUp {
                    TextField(text.displayName, text: $displayName)
                }
                SecureField(text.password, text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                if mode == .signUp {
                    SecureField(text.confirmPassword, text: $confirmPassword)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)

            if let message = validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            if viewModel.isAuthBusy {
                ProgressView().controlSize(.small)
            } else {
                Button(mode == .signIn ? text.signInButton : text.signUpButton) {
                    Task { await submit() }
                }
                .disabled(!canSubmit)
            }

            Button(mode == .signIn ? text.switchToSignUp : text.switchToSignIn) {
                mode = mode == .signIn ? .signUp : .signIn
                viewModel.authError = nil
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(Theme.accentStrong)
        }
        .padding(.top, 10)
    }

    /// 本地校验:格式明显不对就别浪费一次请求。
    private var validationMessage: String? {
        if !password.isEmpty, password.count < 8 { return text.passwordTooShort }
        if mode == .signUp, !confirmPassword.isEmpty, confirmPassword != password {
            return text.passwordMismatch
        }
        return nil
    }

    private var canSubmit: Bool {
        guard email.contains("@"), password.count >= 8 else { return false }
        guard mode == .signUp else { return true }
        return !displayName.trimmingCharacters(in: .whitespaces).isEmpty && confirmPassword == password
    }

    private func submit() async {
        switch mode {
        case .signIn:
            await viewModel.signIn(email: email, password: password)
        case .signUp:
            await viewModel.signUp(email: email, password: password, displayName: displayName)
        }
        if viewModel.account != nil {
            password = ""
            confirmPassword = ""
            await viewModel.refreshSessions()
        }
    }

    // MARK: - 已登录:额度 / 权限 / 设备

    @ViewBuilder
    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            identityHeader
            quotaSection
            permissionsSection
            sessionsSection
            passwordSection
            deleteAccountSection
            footerButtons
        }
        .padding(28)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var identityHeader: some View {
        HStack(spacing: 12) {
            AccountAvatar(
                displayName: viewModel.account?.displayName ?? "?",
                avatarURL: viewModel.me?.user.avatar_url,
                size: 44
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(text.planLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    PlanBadge(plan: viewModel.account?.plan ?? "")
                    if !providerLabels.isEmpty {
                        Text(text.providersLabel)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .padding(.leading, 4)
                        ForEach(providerLabels, id: \.self) { label in
                            ProviderBadge(label: label)
                        }
                    }
                }
            }
            Spacer()
        }
    }

    /// 纯社交账户可能只有占位邮箱,显示名更认得出人。
    private var headerTitle: String {
        let email = viewModel.account?.email ?? ""
        return email.isEmpty ? (viewModel.account?.displayName ?? "") : email
    }

    /// "password" 是本地词(邮箱),GitHub / Apple 用原名。
    private var providerLabels: [String] {
        (viewModel.me?.user.providers ?? []).map { provider in
            switch provider {
            case "github": "GitHub"
            case "apple": "Apple"
            case "password": text.providerPassword
            default: provider
            }
        }
    }

    /// 后端没给 `has_password` 时按「有密码」处理(老后端兼容)。
    private var hasPassword: Bool { viewModel.me?.user.has_password ?? true }

    @ViewBuilder
    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            quotaRow(title: text.quotaChat, bucket: viewModel.me?.quota["chat"])
            quotaRow(title: text.quotaMarket, bucket: viewModel.me?.quota["market"])
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func quotaRow(title: String, bucket: QuotaBucket?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(usageText(bucket))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            if let bucket, let limit = bucket.limit, limit > 0 {
                QuotaBar(fraction: min(Double(bucket.used) / Double(limit), 1))
            }
            if let bucket, !bucket.reset_at.isEmpty {
                Text(String(format: text.resetsAtFormat, Self.readableTimestamp(bucket.reset_at)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    /// 后端给的是 ISO8601 UTC,展示成本地时区的「年-月-日 时:分」;解析不了就原样显示。
    static func readableTimestamp(_ raw: String) -> String {
        guard let date = try? Date.ISO8601FormatStyle().parse(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func usageText(_ bucket: QuotaBucket?) -> String {
        guard let bucket else { return "—" }
        guard let limit = bucket.limit else { return "\(bucket.used) / \(text.unlimited)" }
        return "\(bucket.used) / \(limit)"
    }

    @ViewBuilder
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            chipGroup(
                title: text.permissionsModels,
                labels: viewModel.me?.permissions.models.map(\.display_name) ?? []
            )
            chipGroup(
                title: text.permissionsSources,
                labels: viewModel.me?.permissions.market_sources.map {
                    "\($0.label) · \($0.paths.joined(separator: " / "))"
                } ?? []
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    private func chipGroup(title: String, labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            if labels.isEmpty {
                Text("—").font(.callout).foregroundStyle(Theme.disabled)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.sessionsHeader)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            ForEach(viewModel.sessions) { session in
                HStack(spacing: 8) {
                    Text(session.client)
                        .font(.callout)
                        .foregroundStyle(Theme.text)
                    Text(Self.readableTimestamp(session.created_at))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    // 最近使用才是认得出「这台是不是我」的那一栏。
                    Text(String(format: text.lastUsedFormat, Self.readableTimestamp(session.last_used_at)))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    if session.current {
                        Text(text.currentSession)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.up)
                    }
                    Spacer()
                    if !session.current {
                        Button(text.revoke) {
                            Task { await viewModel.revokeSession(id: session.id) }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Theme.down)
                    }
                }
                .padding(.vertical, 2)
            }
            if viewModel.sessions.isEmpty {
                Text("—").font(.callout).foregroundStyle(Theme.disabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var passwordSection: some View {
        DisclosureGroup(hasPassword ? text.changePassword : text.setPassword) {
            VStack(alignment: .leading, spacing: 8) {
                if hasPassword {
                    SecureField(text.currentPassword, text: $currentPassword)
                } else {
                    // 纯社交账户没有旧密码可填,后端收空的 current_password。
                    Text(text.setPasswordHint)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SecureField(text.newPassword, text: $newPassword)
                HStack(spacing: 10) {
                    Button(hasPassword ? text.changePassword : text.setPassword) {
                        Task { await submitPasswordChange() }
                    }
                    .disabled((hasPassword && currentPassword.count < 8) || newPassword.count < 8 || isChangingPassword)
                    if isChangingPassword { ProgressView().controlSize(.small) }
                    if let passwordNotice {
                        Text(passwordNotice)
                            .font(.caption)
                            .foregroundStyle(passwordNotice == text.passwordUpdated ? Theme.up : Theme.down)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if passwordNeedsReauth { reauthButton }
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 280, alignment: .leading)
            .padding(.top, 8)
        }
        .font(.callout)
        .foregroundStyle(Theme.text)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    private func submitPasswordChange() async {
        guard newPassword.count >= 8 else {
            passwordNotice = text.passwordTooShort
            return
        }
        isChangingPassword = true
        passwordNeedsReauth = false
        do {
            // 首次设密:current 传空串,后端据此放行。
            try await viewModel.changePassword(
                current: hasPassword ? currentPassword : "", new: newPassword
            )
            passwordNotice = text.passwordUpdated
            currentPassword = ""
            newPassword = ""
        } catch {
            passwordNotice = text.describe(error)
            passwordNeedsReauth = Self.needsReauth(error)
        }
        isChangingPassword = false
    }

    /// App Store 5.1.1(v):注册入口在 app 内,注销入口也必须在 app 内。
    @ViewBuilder
    private var deleteAccountSection: some View {
        DisclosureGroup(text.deleteAccount) {
            VStack(alignment: .leading, spacing: 8) {
                Text(text.deleteAccountWarning)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                // 无密码账户没有可输的密码,拦截只靠下面那次二次确认。
                if hasPassword {
                    SecureField(text.deleteAccountPasswordPrompt, text: $deletePassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
                HStack(spacing: 10) {
                    Button(text.deleteAccount, role: .destructive) {
                        deleteError = nil
                        showDeleteConfirmation = true
                    }
                    .disabled((hasPassword && deletePassword.count < 8) || isDeleting)
                    if isDeleting { ProgressView().controlSize(.small) }
                    if let deleteError {
                        Text(deleteError)
                            .font(.caption)
                            .foregroundStyle(Theme.down)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if deleteNeedsReauth { reauthButton }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .font(.callout)
        .foregroundStyle(Theme.down)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.down.opacity(0.45), lineWidth: 1))
        .alert(text.deleteAccount, isPresented: $showDeleteConfirmation) {
            Button(text.cancel, role: .cancel) {}
            Button(text.deleteAccountConfirm, role: .destructive) {
                Task { await submitDeleteAccount() }
            }
        } message: {
            Text(text.deleteAccountWarning)
        }
    }

    /// 密码错误只会拿到 401 invalid_credentials,后端保留会话——
    /// 这里内联展示后端原话,绝不能顺手把人登出。
    private func submitDeleteAccount() async {
        isDeleting = true
        deleteError = nil
        deleteNeedsReauth = false
        do {
            try await viewModel.deleteAccount(password: hasPassword ? deletePassword : nil)
            deletePassword = ""
        } catch {
            deleteError = text.describe(error)
            deleteNeedsReauth = Self.needsReauth(error)
        }
        isDeleting = false
    }

    /// 无密码账户的设密 / 删号要求「刚登录过」的会话(后端 15 分钟),
    /// 否则 403 `reauth_required`——被盗令牌没法悄悄装后门。
    static func needsReauth(_ error: any Error) -> Bool {
        (error as? AccountError)?.code == "reauth_required"
    }

    /// 只清本地登录态、回到登录页;后端会话留给它自己过期(反正已经不新鲜了)。
    private var reauthButton: some View {
        Button(text.reauthSignInAgain) {
            passwordNeedsReauth = false
            deleteNeedsReauth = false
            viewModel.signOutLocally()
        }
        .font(.caption)
    }

    private var footerButtons: some View {
        HStack(spacing: 10) {
            Button(text.refresh) {
                Task {
                    await viewModel.refreshMe()
                    await viewModel.refreshSessions()
                }
            }
            Spacer()
            Button(text.signOut) { Task { await viewModel.signOut() } }
            Button(text.signOutAll, role: .destructive) { Task { await viewModel.signOutAll() } }
        }
    }
}

/// 额度条。系统 ProgressView 的 tint 在设置窗口里不生效,自己画两条圆角矩形。
struct QuotaBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.elevated)
                RoundedRectangle(cornerRadius: 3)
                    .fill(fraction >= 1 ? Theme.down : Theme.accent)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

/// 套餐小徽章:accentSoft 底 + accent 字。
struct PlanBadge: View {
    let plan: String

    var body: some View {
        Text(plan.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.accentStrong)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// 头像:社交账户拉 `avatar_url`,拉不到或没有(邮箱账户)就显示首字母圈。
struct AccountAvatar: View {
    let displayName: String
    /// 后端 `user.avatar_url`;空串或非法地址都按「没有头像」处理。
    var avatarURL: String?
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url = avatarURL.flatMap({ $0.isEmpty ? nil : URL(string: $0) }) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsCircle
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(Theme.accentSoft)
            Text(String(displayName.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(Theme.accentStrong)
        }
    }
}

/// 登录方式徽章(GitHub / Apple / 邮箱)。
struct ProviderBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
