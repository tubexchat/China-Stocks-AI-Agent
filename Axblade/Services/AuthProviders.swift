import Foundation
import AppKit
import AuthenticationServices
import CryptoKit

/// 登录过程中需要用户配合的事件。目前只有 GitHub 设备码这一种。
enum AuthProgress: Equatable, Sendable {
    case userCode(String, verificationURL: URL)
}

/// 原生 Sign in with Apple 拿到的、要交给后端验签的东西。
/// 姓名只有**首次**授权时才有,之后是 nil。
struct AppleCredential: Equatable, Sendable {
    var identityToken: String
    var fullName: String?
    /// 明文 nonce(发给后端);Apple 令牌里的 `nonce` 声明是它的 sha256。
    var nonce: String = ""
}

/// Apple 登录的防重放随机数。
///
/// 发起授权时把 **sha256(raw) 的十六进制**设进 `ASAuthorizationAppleIDRequest.nonce`,
/// Apple 会把这串原样写进 id_token 的 `nonce` 声明;明文 raw 随请求发给后端,
/// 后端比对 `claims.nonce == sha256(raw)`,对不上就 401 `invalid_identity_token`。
/// 截获到的旧 id_token 因此没法拿去换令牌——它的 nonce 声明配不上新的 raw。
enum AppleNonce {
    /// 32 字节随机数编成 base64url(43 个 `[A-Za-z0-9_-]` 字符),
    /// 落在后端要求的 8–64 位 urlsafe 区间里。
    static func make() -> (raw: String, hashed: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // 系统随机源拿不到时退回 Swift 的随机数,总之不能发一个固定值。
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        }
        let raw = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return (raw, hash(raw))
    }

    /// 后端算的是 `hashlib.sha256(nonce.encode()).hexdigest()`,这里必须逐字对齐:
    /// 小写十六进制,不是 base64。
    static func hash(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// 只描述**客户端本地**的失败;后端的失败一律走 `AccountError.http`(用后端文案)。
enum AppleSignInError: LocalizedError, Equatable {
    /// 缺 `com.apple.developer.applesignin` entitlement(ad-hoc / Debug 构建)。
    /// 系统这时给的是 `ASAuthorizationError.unknown`(1000)。
    case needsSignedBuild
    case canceled
    case missingIdentityToken
}

/// `ASAuthorizationAppleIDCredential` → `AppleCredential` 的纯函数部分,可单测。
enum AppleCredentialMapper {
    static func fullName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter
            .localizedString(from: components, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    static func credential(
        identityToken: Data?, fullName: PersonNameComponents?, nonce: String = ""
    ) throws -> AppleCredential {
        guard let identityToken, let token = String(data: identityToken, encoding: .utf8), !token.isEmpty
        else { throw AppleSignInError.missingIdentityToken }
        return AppleCredential(
            identityToken: token, fullName: self.fullName(from: fullName), nonce: nonce
        )
    }

    /// 缺 entitlement 的 ad-hoc 构建里系统只给 unknown(1000),
    /// 直译成「未知错误」用户根本看不懂,这里翻成「换个登录方式」。
    static func translate(_ error: any Error) -> any Error {
        switch (error as? ASAuthorizationError)?.code {
        case .unknown: AppleSignInError.needsSignedBuild
        case .canceled: AppleSignInError.canceled
        default: error
        }
    }
}

/// `ASAuthorizationController` 的 async 包装。
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleCredential, any Error>?
    /// controller 对 delegate 是弱引用,流程期间自持,防止提前释放。
    private var selfRetain: AppleSignInCoordinator?
    /// 本次授权的明文 nonce,回调时随凭据一起交出去。
    private var nonce = ""

    /// 请求的构造是纯的,单独抽出来好断言 `nonce` 确实是 sha256 十六进制。
    static func request(hashedNonce: String) -> ASAuthorizationAppleIDRequest {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce
        return request
    }

    func run() async throws -> AppleCredential {
        let nonce = AppleNonce.make()
        self.nonce = nonce.raw
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.selfRetain = self
            let controller = ASAuthorizationController(
                authorizationRequests: [Self.request(hashedNonce: nonce.hashed)]
            )
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleCredential, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
        selfRetain = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure(AppleSignInError.missingIdentityToken))
            return
        }
        let nonce = self.nonce
        finish(Result {
            try AppleCredentialMapper.credential(
                identityToken: credential.identityToken, fullName: credential.fullName, nonce: nonce
            )
        })
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        finish(.failure(AppleCredentialMapper.translate(error)))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
