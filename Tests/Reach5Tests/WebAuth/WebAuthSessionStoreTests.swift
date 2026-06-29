import XCTest
import AuthenticationServices
@testable import Reach5

@MainActor
final class WebAuthSessionStoreTests: XCTestCase {

    private let provider = DummyContextProvider()

    private func authorizeURL(state: String) -> URL {
        URL(string: "https://r5.example.com/authorize?state=\(state)")!
    }

    private func callback(state: String) -> URL {
        URL(string: "https://host.example.com/cb?code=code-\(state)&state=\(state)")!
    }

    // #1 : aucune session en vol → le lien n'est pas consommé.
    func testCompleteReturnsFalseWhenNoSessionInFlight() {
        let store = WebAuthSessionStore(makeSession: { FakeRunner() })
        XCTAssertFalse(store.complete(externalCallbackURL: callback(state: "whatever")))
    }

    // #2 : deux logins concurrents, chaque callback complète SA session (routage par state).
    func testRoutesCallbackToMatchingSessionByState() async throws {
        let f1 = FakeRunner(), f2 = FakeRunner()
        var queue: [FakeRunner] = [f1, f2]
        let store = WebAuthSessionStore(makeSession: { queue.removeFirst() })

        async let login1 = store.run(
            routing: WebAuthRouting(state: "s1", expectedCallback: nil),
            url: authorizeURL(state: "s1"), callbackURLScheme: "scheme",
            presentationContextProvider: provider, prefersEphemeralWebBrowserSession: false)
        async let login2 = store.run(
            routing: WebAuthRouting(state: "s2", expectedCallback: nil),
            url: authorizeURL(state: "s2"), callbackURLScheme: "scheme",
            presentationContextProvider: provider, prefersEphemeralWebBrowserSession: false)

        // Les deux sessions doivent être enregistrées avant de compléter.
        await f1.waitUntilStarted()
        await f2.waitUntilStarted()

        // On complète dans l'ordre inverse pour bien vérifier que c'est le state qui route.
        XCTAssertTrue(store.complete(externalCallbackURL: callback(state: "s2")))
        XCTAssertTrue(store.complete(externalCallbackURL: callback(state: "s1")))

        let result1 = try await login1
        let result2 = try await login2
        XCTAssertEqual(result1, callback(state: "s1"))
        XCTAssertEqual(result2, callback(state: "s2"))
    }

    // #1 / idempotence : une fois la session terminée, un second callback n'est plus consommé.
    func testCompleteIsFalseAfterSessionFinished() async throws {
        let fake = FakeRunner()
        var queue: [FakeRunner] = [fake]
        let store = WebAuthSessionStore(makeSession: { queue.removeFirst() })

        async let login = store.run(
            routing: WebAuthRouting(state: "s", expectedCallback: nil),
            url: authorizeURL(state: "s"), callbackURLScheme: "scheme",
            presentationContextProvider: provider, prefersEphemeralWebBrowserSession: false)

        await fake.waitUntilStarted()
        XCTAssertTrue(store.complete(externalCallbackURL: callback(state: "s")))
        _ = try await login // run() retourne → defer retire l'entrée

        XCTAssertFalse(store.complete(externalCallbackURL: callback(state: "s")))
    }
}
