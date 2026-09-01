import XCTest
@testable import Reach5

/// The hook an app pinning the server's certificate uses instead of swizzling `URLSession`. What matters is
/// that it reaches every call the SDK makes, `/oauth/authorize` included: an app that pins some of them pins
/// nothing.
final class AuthenticationChallengeHandlerTests: XCTestCase {
    private var networkClient: NetworkClient!

    override func setUp() {
        super.setUp()
        ChallengingURLProtocol.outcomes.reset()
    }

    override func tearDown() {
        networkClient = nil
        ChallengingURLProtocol.outcomes.reset()
        super.tearDown()
    }

    private func makeClient(handler: AuthenticationChallengeHandler?) -> NetworkClient {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return NetworkClient(
            decoder: decoder,
            configuration: ChallengingURLProtocol.makeSessionConfiguration(),
            authenticationChallengeHandler: handler
        )
    }

    func testHandlerAnswersTheChallengeOfAnOrdinaryCall() async throws {
        let seen = ChallengeRecorder()
        networkClient = makeClient(handler: { challenge in
            await seen.record(challenge)
            return (.useCredential, URLCredential(user: "", password: "", persistence: .none))
        })

        try await networkClient
            .request(URL(string: "https://example.com/identity/v1/config")!)
            .responseJson()

        let method = await seen.authenticationMethod
        XCTAssertEqual(method, NSURLAuthenticationMethodServerTrust)
        XCTAssertEqual(ChallengingURLProtocol.outcomes.recorded, .usedCredential)
    }

    /// `/oauth/authorize` is the one call that carries the login, and the only one whose delegate the SDK
    /// answers for itself. The handler must reach it all the same.
    func testHandlerAlsoAnswersTheChallengeOfTheRedirectCall() async {
        let seen = ChallengeRecorder()
        networkClient = makeClient(handler: { challenge in
            await seen.record(challenge)
            return (.cancelAuthenticationChallenge, nil)
        })

        _ = try? await networkClient
            .request(URL(string: "https://example.com/oauth/authorize")!)
            .redirect()

        let method = await seen.authenticationMethod
        XCTAssertEqual(method, NSURLAuthenticationMethodServerTrust)
        // The challenge's own sender is never told: `URLSession` cancels the task itself on
        // `.cancelAuthenticationChallenge` — measured, and asserted as such in the next test.
        XCTAssertNil(ChallengingURLProtocol.outcomes.recorded)
    }

    /// A handler refusing the certificate must reach the caller as the refusal it is, not as one of the
    /// redirection recoveries `redirect()` performs.
    ///
    /// `URLSession` reports that refusal as a plain `cancelled` — measured; it does not keep the trust
    /// failure's own code. An app pinning the certificate therefore cannot tell its own refusal from a
    /// cancellation by the error alone, which is worth knowing before reading such a log.
    func testRefusedChallengeSurfacesAsACancellation() async {
        networkClient = makeClient(handler: { _ in (.cancelAuthenticationChallenge, nil) })

        do {
            _ = try await networkClient
                .request(URL(string: "https://example.com/oauth/authorize")!)
                .redirect()
            XCTFail("attendu : une erreur")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("attendu : URLError, obtenu \(error)")
        }
    }

    /// Without a handler the SDK installs no delegate of its own on the shared session, and the system keeps
    /// answering challenges — the behaviour every app that does not pin depends on.
    func testWithoutHandlerTheSystemKeepsAnsweringChallenges() async throws {
        networkClient = makeClient(handler: nil)

        try await networkClient
            .request(URL(string: "https://example.com/identity/v1/config")!)
            .responseJson()

        XCTAssertEqual(ChallengingURLProtocol.outcomes.recorded, .performedDefaultHandling)
    }
}

/// Records the challenge the handler was given, from whichever thread it runs on.
private actor ChallengeRecorder {
    private var challenge: URLAuthenticationChallenge?

    func record(_ challenge: URLAuthenticationChallenge) {
        self.challenge = challenge
    }

    var authenticationMethod: String? {
        challenge?.protectionSpace.authenticationMethod
    }
}
