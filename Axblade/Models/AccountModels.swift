import Foundation

// 后端账户接口(spec 1.4 / 1.5)的数据形状。字段名与后端 JSON 一一对应,
// 因此这里保留 snake_case,免得为了 CodingKeys 维护两份名字。

/// 一条额度:`limit == nil` 表示不限。
struct QuotaBucket: Codable, Equatable, Sendable {
    var limit: Int?
    var used: Int
    var remaining: Int?
    var reset_at: String
}

/// 当前主体有权限使用的模型。
struct ModelPermission: Codable, Equatable, Sendable, Identifiable {
    var alias: String
    var display_name: String

    var id: String { alias }
}

/// 当前主体有权限使用的行情源(以及放行的路径)。
struct MarketSourcePermission: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var label: String
    var paths: [String]
}

/// legacy 主体的 `email` 为 null,`kind == "legacy"`。
struct MeUser: Codable, Equatable, Sendable {
    var id: Int
    var email: String?
    var display_name: String
    var plan: String
    var created_at: String
    var kind: String
    /// v0.3.1:社交登录带来的头像地址;没有时是空串。
    var avatar_url: String
    /// 已关联的登录方式,如 `["github","password"]`。
    var providers: [String]
    /// 纯社交账户没有密码:改密即「首次设置密码」,删号无需密码。
    var has_password: Bool

    init(
        id: Int, email: String?, display_name: String, plan: String, created_at: String, kind: String,
        avatar_url: String = "", providers: [String] = [], has_password: Bool = true
    ) {
        self.id = id
        self.email = email
        self.display_name = display_name
        self.plan = plan
        self.created_at = created_at
        self.kind = kind
        self.avatar_url = avatar_url
        self.providers = providers
        self.has_password = has_password
    }

    /// 三个新字段是 v0.3.1 才有的:老后端不发、或发 null 时都按缺省处理,
    /// 而不是让整份 `/v1/me` 解析失败(那会把用户直接踢成未登录)。
    /// `has_password` 缺省按 true——少显示一个「当前密码」框比多显示一个更糟。
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        display_name = try container.decode(String.self, forKey: .display_name)
        plan = try container.decode(String.self, forKey: .plan)
        created_at = try container.decode(String.self, forKey: .created_at)
        kind = try container.decode(String.self, forKey: .kind)
        avatar_url = try container.decodeIfPresent(String.self, forKey: .avatar_url) ?? ""
        providers = try container.decodeIfPresent([String].self, forKey: .providers) ?? []
        has_password = try container.decodeIfPresent(Bool.self, forKey: .has_password) ?? true
    }

    enum CodingKeys: String, CodingKey {
        case id, email, display_name, plan, created_at, kind, avatar_url, providers, has_password
    }

    /// 展示用的登录方式徽章顺序按后端给的来,未知 provider 原样透出。
    var providerLabels: [String] {
        providers.map { provider in
            switch provider {
            case "github": "GitHub"
            case "apple": "Apple"
            default: provider
            }
        }
    }
}

// MARK: - 社交登录(spec 1.4b)

/// `POST /v1/auth/github/device` 的响应。设备码流程由**我们的后端**代理,
/// GitHub 的 client secret 不在客户端。
struct DeviceCode: Codable, Equatable, Sendable {
    var device_code: String
    var user_code: String
    var verification_uri: String
    /// 后端(GitHub)要求的轮询间隔,单位秒;缺省按 GitHub 文档的 5 秒。
    var interval: Int?
    var expires_in: Int?

    var verificationURL: URL? { URL(string: verification_uri) }

    /// 至少 1 秒:后端某天回 0 也不能变成打满 CPU 的死循环。
    var pollInterval: Double { Double(max(interval ?? 5, 1)) }
}

/// `POST /v1/auth/github/device/poll` 的两种结局。
/// 410 / 403 / 502 走 `AccountError.http`,文案用后端的。
enum GitHubPoll: Equatable, Sendable {
    /// 用户还没在浏览器里授权。`interval` 非 nil 表示后端要求换一个轮询间隔(slow_down)。
    case pending(interval: Int?)
    case signedIn(token: String, user: MeUser)
}

/// 签发令牌的接口(登录 / 注册 / 设备码轮询成功 / Apple)共用的响应形状。
struct SignedInResponse: Decodable, Sendable {
    var token: String
    var user: MeUser
}

/// 202 的响应体。
struct PendingPoll: Decodable, Sendable {
    var pending: Bool
    var interval: Int?
}

struct MePlan: Codable, Equatable, Sendable {
    var name: String
    var chat_requests_per_day: Int?
    var market_requests_per_day: Int?
}

struct MeSession: Codable, Equatable, Sendable {
    var id: Int
    var client: String
    var created_at: String
}

/// `GET /v1/me` 的完整响应。
struct MeResponse: Codable, Equatable, Sendable {
    var user: MeUser
    var plan: MePlan
    /// key 目前是 "chat" / "market"。
    var quota: [String: QuotaBucket]
    var permissions: Permissions
    /// legacy 主体没有会话。
    var session: MeSession?

    struct Permissions: Codable, Equatable, Sendable {
        var models: [ModelPermission]
        var market_sources: [MarketSourcePermission]
    }
}

/// `GET /v1/me/sessions` 里的一行。
struct SessionRow: Codable, Equatable, Sendable, Identifiable {
    var id: Int
    var client: String
    var created_at: String
    var last_used_at: String
    var current: Bool
}

/// `GET /v1/me/usage` 里的一天(后端已补零并升序)。
struct UsageDay: Codable, Equatable, Sendable, Identifiable {
    var day: String
    var chat_requests: Int
    var chat_tokens: Int
    var market_requests: Int

    var id: String { day }
}

/// 本地缓存的账户摘要(不含令牌),存 account.json 供离线启动显示。
struct UserAccount: Codable, Equatable, Sendable {
    var email: String
    var displayName: String
    var plan: String
}
