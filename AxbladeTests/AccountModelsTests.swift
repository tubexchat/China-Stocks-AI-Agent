import XCTest
@testable import Axblade

final class AccountModelsTests: XCTestCase {
    func testAccountSummaryRoundTripsThroughJSON() throws {
        let account = UserAccount(email: "a@b.c", displayName: "Nick", plan: "free")

        let data = try JSONCoding.encoder().encode(account)
        let decoded = try JSONCoding.decoder().decode(UserAccount.self, from: data)

        XCTAssertEqual(decoded, account)
    }

    /// 本地摘要里不许出现令牌,account.json 泄露也拿不到凭据。
    func testAccountSummaryCarriesNoToken() throws {
        let data = try JSONCoding.encoder().encode(
            UserAccount(email: "a@b.c", displayName: "Nick", plan: "pro")
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.lowercased().contains("token"))
        XCTAssertFalse(json.lowercased().contains("secret"))
    }

    /// 老版本的 account.json(GitHub/Apple 时代)解不出来就当未登录,不能崩。
    func testLegacyAccountJSONDecodesToNil() throws {
        let legacy = """
        {"provider":"github","id":"12345","displayName":"Nick","handle":"nick","linkedAt":"2026-08-01T00:00:00.000Z"}
        """

        XCTAssertNil(try? JSONCoding.decoder().decode(UserAccount.self, from: Data(legacy.utf8)))
    }

    func testMeResponseDecodesFromTheBackendShape() throws {
        let json = """
        {"user":{"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user"},
         "plan":{"name":"free","chat_requests_per_day":50,"market_requests_per_day":500},
         "quota":{"chat":{"limit":50,"used":3,"remaining":47,"reset_at":"r"}},
         "permissions":{"models":[{"alias":"deepseek","display_name":"DeepSeek-V4-Flash-0731"}],
                        "market_sources":[{"id":"binance","label":"Binance Spot","paths":["klines"]}]},
         "session":{"id":3,"client":"mac","created_at":"t"}}
        """

        let me = try JSONCoding.decoder().decode(MeResponse.self, from: Data(json.utf8))

        XCTAssertEqual(me.user.display_name, "A")
        XCTAssertEqual(me.quota["chat"]?.remaining, 47)
        XCTAssertEqual(me.permissions.models.map(\.id), ["deepseek"])
        XCTAssertEqual(me.permissions.market_sources.first?.label, "Binance Spot")
        XCTAssertEqual(me.session?.id, 3)
    }

    func testUsageDayAndSessionRowAreIdentifiable() throws {
        let usage = try JSONCoding.decoder().decode(
            UsageDay.self,
            from: Data(#"{"day":"2026-08-18","chat_requests":1,"chat_tokens":2,"market_requests":3}"#.utf8)
        )
        let session = try JSONCoding.decoder().decode(
            SessionRow.self,
            from: Data(#"{"id":7,"client":"web","created_at":"a","last_used_at":"b","current":false}"#.utf8)
        )

        XCTAssertEqual(usage.id, "2026-08-18")
        XCTAssertEqual(session.id, 7)
        XCTAssertFalse(session.current)
    }

    /// 旧版 settings.json(多 provider 时代的字段)必须能解码:
    /// 老字段直接忽略,落到默认后端模型,不崩、不丢数据源开关。
    func testLegacySettingsJSONStillDecodes() throws {
        let legacy = """
        {
          "defaultProviderID" : "11111111-2222-3333-4444-555555555555",
          "providers" : [
            {
              "baseURL" : "https://api.openai.com/v1",
              "id" : "11111111-2222-3333-4444-555555555555",
              "kind" : "openaiCompatible",
              "model" : "gpt-4o-mini",
              "name" : "OpenAI"
            }
          ]
        }
        """
        let settings = try JSONCoding.decoder().decode(AppSettings.self, from: Data(legacy.utf8))

        XCTAssertEqual(settings.modelAlias, Backend.defaultModelAlias)
        XCTAssertTrue(settings.disabledSources.isEmpty)
    }

    func testDisabledSourcesRoundTrip() throws {
        var settings = AppSettings()
        settings.disabledSources = [.okx, .krStock]

        let data = try JSONCoding.encoder().encode(settings)
        let decoded = try JSONCoding.decoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.disabledSources, [.okx, .krStock])
    }
}

/// v0.3.1 社交登录带来的字段与形状(spec 1.4b)。
final class SocialLoginModelsTests: XCTestCase {
    /// `user` 多了 avatar_url / providers / has_password,三个都要解出来。
    func testMeUserDecodesSocialFields() throws {
        let json = """
        {"id":12,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user",
         "avatar_url":"https://avatars.githubusercontent.com/u/1?v=4",
         "providers":["github","password"],"has_password":true}
        """

        let user = try JSONCoding.decoder().decode(MeUser.self, from: Data(json.utf8))

        XCTAssertEqual(user.avatar_url, "https://avatars.githubusercontent.com/u/1?v=4")
        XCTAssertEqual(user.providers, ["github", "password"])
        XCTAssertTrue(user.has_password)
    }

    /// 纯社交账户:没有密码,providers 里也没有 password。
    func testMeUserDecodesPasswordlessSocialAccount() throws {
        let json = """
        {"id":13,"email":"x@privaterelay.appleid.com","display_name":"X","plan":"free",
         "created_at":"t","kind":"user","avatar_url":"","providers":["apple"],"has_password":false}
        """

        let user = try JSONCoding.decoder().decode(MeUser.self, from: Data(json.utf8))

        XCTAssertFalse(user.has_password)
        XCTAssertEqual(user.providers, ["apple"])
        XCTAssertTrue(user.avatar_url.isEmpty)
    }

    /// 老后端(0.3.0)不发这三个字段,整份 /v1/me 不能因此解析失败。
    func testMeUserWithoutSocialFieldsFallsBackToDefaults() throws {
        let json = """
        {"id":1,"email":"a@b.c","display_name":"A","plan":"free","created_at":"t","kind":"user"}
        """

        let user = try JSONCoding.decoder().decode(MeUser.self, from: Data(json.utf8))

        XCTAssertEqual(user.avatar_url, "")
        XCTAssertEqual(user.providers, [])
        XCTAssertTrue(user.has_password, "没有该字段时按「有密码」处理,改密表单才不会缺当前密码框")
    }

    /// null 也当缺省,后端某天把头像置空不能把客户端解崩。
    func testMeUserToleratesNullSocialFields() throws {
        let json = """
        {"id":1,"email":null,"display_name":"A","plan":"free","created_at":"t","kind":"legacy",
         "avatar_url":null,"providers":null,"has_password":null}
        """

        let user = try JSONCoding.decoder().decode(MeUser.self, from: Data(json.utf8))

        XCTAssertEqual(user.avatar_url, "")
        XCTAssertEqual(user.providers, [])
    }

    func testDeviceCodeDecodesAndExposesVerificationURL() throws {
        let json = """
        {"device_code":"dc_1","user_code":"5DA3-EC78",
         "verification_uri":"https://github.com/login/device","expires_in":899,"interval":5}
        """

        let device = try JSONCoding.decoder().decode(DeviceCode.self, from: Data(json.utf8))

        XCTAssertEqual(device.device_code, "dc_1")
        XCTAssertEqual(device.user_code, "5DA3-EC78")
        XCTAssertEqual(device.verificationURL, URL(string: "https://github.com/login/device"))
        XCTAssertEqual(device.pollInterval, 5)
    }

    /// interval 缺省时用 GitHub 文档的 5 秒,别退化成 0 秒死循环。
    func testDeviceCodeWithoutIntervalFallsBackToFiveSeconds() throws {
        let json = #"{"device_code":"dc","user_code":"AAAA-BBBB","verification_uri":"https://github.com/login/device"}"#

        let device = try JSONCoding.decoder().decode(DeviceCode.self, from: Data(json.utf8))

        XCTAssertEqual(device.pollInterval, 5)
    }
}
