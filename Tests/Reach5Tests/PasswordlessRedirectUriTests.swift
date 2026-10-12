import XCTest
@testable import Reach5

final class PasswordlessRedirectUriTests: XCTestCase {
    private let integratorRedirectUri = URL(string: "https://example.com/account/email-validation")!

    override func setUp() {
        super.setUp()
        FakeIdentityBackend.reset()
    }

    private func makeReachFive() -> ReachFive {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FakeIdentityBackend.self]
        return ReachFive(
            sdkConfig: SdkConfig(domain: "example.reach5.net", clientId: "testclient"),
            storage: InMemoryStorage(),
            sdkInternalConfig: SdkInternalConfig(loggingEnabled: false, sessionConfiguration: sessionConfiguration)
        )
    }

    func testVerifyPasswordlessCodeExchangesTheCodeWithTheRedirectUriGivenToStartPasswordless() async throws {
        let reachFive = makeReachFive()

        try await reachFive.startPasswordless(.Email(email: "jane@example.com", redirectUri: integratorRedirectUri))
        let token = try await reachFive.verifyPasswordlessCode(verifyAuthCodeRequest: VerifyAuthCodeRequest(
            authType: .MagicLink,
            email: "jane@example.com",
            verificationCode: "123456"
        ))

        XCTAssertEqual(token.accessToken, "the-access-token")
        XCTAssertEqual(FakeIdentityBackend.tokenRedirectUri, integratorRedirectUri.absoluteString)
    }

    func testVerifyPasswordlessCodeExchangesTheCodeWithTheSdkRedirectUriWhenStartPasswordlessGotNone() async throws {
        let reachFive = makeReachFive()

        try await reachFive.startPasswordless(.Email(email: "jane@example.com", redirectUri: nil))
        let token = try await reachFive.verifyPasswordlessCode(verifyAuthCodeRequest: VerifyAuthCodeRequest(
            authType: .MagicLink,
            email: "jane@example.com",
            verificationCode: "123456"
        ))

        XCTAssertEqual(token.accessToken, "the-access-token")
        XCTAssertEqual(FakeIdentityBackend.tokenRedirectUri, "reachfive-testclient://callback")
    }

    func testInterceptedMagicLinkExchangesTheCodeWithTheRedirectUriGivenToStartPasswordless() async throws {
        let reachFive = makeReachFive()
        let callback = expectation(description: "passwordless callback")
        var result: Result<AuthToken, ReachFiveError>?
        reachFive.addPasswordlessCallback { callbackResult in
            result = callbackResult
            callback.fulfill()
        }

        try await reachFive.startPasswordless(.Email(email: "jane@example.com", redirectUri: integratorRedirectUri))
        reachFive.interceptUrl(URL(string: "\(integratorRedirectUri.absoluteString)?code=the-code")!)
        await fulfillment(of: [callback], timeout: 5)

        XCTAssertEqual(try result?.get().accessToken, "the-access-token")
        XCTAssertEqual(FakeIdentityBackend.tokenRedirectUri, integratorRedirectUri.absoluteString)
    }
}

private final class InMemoryStorage: Storage {
    private var values: [String: Data] = [:]

    func save(key: String, value: some Codable) {
        values[key] = try? JSONEncoder().encode(value)
    }

    func get<D: Codable>(key: String) -> D? {
        values[key].flatMap { try? JSONDecoder().decode(D.self, from: $0) }
    }

    func take<D: Codable>(key: String) -> D? {
        defer { clear(key: key) }
        return get(key: key)
    }

    func clear(key: String) {
        values.removeValue(forKey: key)
    }
}

/// Answers the passwordless endpoints the way the ReachFive backend does: the authorization code is bound to
/// the `redirect_uri` sent to `/passwordless/start`, and `/oauth/token` refuses any other one.
private final class FakeIdentityBackend: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var startRedirectUri: String?
    nonisolated(unsafe) private(set) static var tokenRedirectUri: String?

    static func reset() {
        lock.withLock {
            startRedirectUri = nil
            tokenRedirectUri = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.reach5.net"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.jsonBody(of: request)
        let (status, response): (Int, [String: Any]) = Self.lock.withLock {
            switch request.url?.path {
            case "/identity/v1/passwordless/start":
                Self.startRedirectUri = body["redirect_uri"] as? String
                return (200, [:])
            case "/identity/v1/verify-auth-code":
                return (200, [:])
            case "/identity/v1/passwordless/verify":
                return (200, ["code": "the-code"])
            case "/oauth/token":
                let redirectUri = body["redirect_uri"] as? String
                Self.tokenRedirectUri = redirectUri
                guard redirectUri == Self.startRedirectUri else {
                    return (400, [
                        "error": "invalid_request",
                        "error_description": "Invalid redirect uri",
                        "error_message_key": "error.redirectUri.invalid",
                    ])
                }
                return (200, ["access_token": "the-access-token", "token_type": "Bearer", "expires_in": 3600])
            default:
                return (404, ["error": "not_found"])
            }
        }

        let httpResponse = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: response))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func jsonBody(of request: URLRequest) -> [String: Any] {
        guard let stream = request.httpBodyStream else {
            return request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
