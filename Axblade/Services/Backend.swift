import Foundation

/// 官方后端可选的一个模型。alias 是发给后端的模型名,后端译成真实接入点。
struct BackendModel: Identifiable, Equatable, Sendable {
    let alias: String
    let displayName: String

    var id: String { alias }
}

/// 官方后端(Axblade API)。客户端所有 AI 请求只打这里;
/// 万擎模型 APIKEY 只存在于服务端,客户端任何地方都不涉及。
/// 客户端**不内置任何访问令牌**:令牌由用户登录后签发,只存钥匙串(见 `TokenStore`)。
enum Backend {
    static let baseURL = "https://api.chillskill.xyz/v1"

    /// displayName 是后端实际推理的完整模型名(见聊天响应的 `model` 字段),
    /// 只用于界面展示;发给后端的仍是 alias,后端换接入点时记得同步这里。
    static let models: [BackendModel] = [
        BackendModel(alias: "deepseek", displayName: "DeepSeek-V4-Flash-0731"),
        BackendModel(alias: "kimi", displayName: "Kimi-K2.7-Code")
    ]
    static let defaultModelAlias = "deepseek"

    /// 别名未命中固定模型表时落回默认,旧配置里的野值不会流向后端。
    static func model(alias: String) -> BackendModel {
        models.first { $0.alias == alias } ?? models[0]
    }
}

/// 后端访问令牌的唯一出入口。明文只在钥匙串里,不进 JSON、不进 UserDefaults、不写日志。
enum TokenStore {
    static let keychainAccount = "auth.backend"

    static func token() -> String? {
        KeychainStore.secret(account: keychainAccount)
    }

    /// 传 nil 即登出:把钥匙串里的令牌删掉。
    /// 返回值 = 钥匙串里现在确实是这个值(写完立刻回读一次),
    /// 写不进去的时候调用方要报错,而不是假装登录成功。
    @discardableResult
    static func set(_ t: String?) -> Bool {
        guard let t else {
            KeychainStore.deleteSecret(account: keychainAccount)
            return token() == nil
        }
        return KeychainStore.setSecret(t, account: keychainAccount) == errSecSuccess && token() == t
    }
}
