import XCTest
@testable import Axblade

final class KeychainStoreTests: XCTestCase {
    private let account = "test.secret.\(UUID().uuidString)"

    override func tearDownWithError() throws {
        KeychainStore.deleteSecret(account: account)
    }

    func testSecretRoundTripsThroughTheKeychain() throws {
        try skipIfKeychainUnavailable()

        KeychainStore.setSecret("gho_token", account: account)

        XCTAssertEqual(KeychainStore.secret(account: account), "gho_token")
    }

    func testWritingTwiceKeepsTheNewestSecret() throws {
        try skipIfKeychainUnavailable()

        KeychainStore.setSecret("old", account: account)
        KeychainStore.setSecret("new", account: account)

        XCTAssertEqual(KeychainStore.secret(account: account), "new")
    }

    func testDeletingRemovesTheSecret() throws {
        try skipIfKeychainUnavailable()

        KeychainStore.setSecret("gho_token", account: account)
        KeychainStore.deleteSecret(account: account)

        XCTAssertNil(KeychainStore.secret(account: account))
    }

    func testUnknownAccountHasNoSecret() {
        XCTAssertNil(KeychainStore.secret(account: "test.unknown.\(UUID().uuidString)"))
    }

    /// 测试宿主是 ad-hoc 签名的沙盒 app,在部分机器上拿不到钥匙串权限;
    /// 那种情况下跳过而不是谎报通过。
    private func skipIfKeychainUnavailable() throws {
        let probe = "test.probe.\(UUID().uuidString)"
        KeychainStore.setSecret("probe", account: probe)
        let readBack = KeychainStore.secret(account: probe)
        KeychainStore.deleteSecret(account: probe)
        try XCTSkipIf(readBack == nil, "当前构建无法访问钥匙串(ad-hoc 签名 + 沙盒)")
    }
}
