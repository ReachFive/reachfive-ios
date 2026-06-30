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

    // Deux sessions en vol en même temps (cas multi-fenêtres iPad/macCatalyst) : chaque callback
    // complète SA session grâce au routage par state.
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

    // Un callback dont le `state` ne correspond à aucune session en vol n'est pas consommé (renvoie
    // false) et ne complète surtout pas une AUTRE session ; la session visée reste en attente de SON
    // propre callback.
    func testCompleteWithNonMatchingStateReturnsFalse() async throws {
        let fake = FakeRunner()
        var queue: [FakeRunner] = [fake]
        let store = WebAuthSessionStore(makeSession: { queue.removeFirst() })

        async let login = store.run(
            routing: WebAuthRouting(state: "expected", expectedCallback: nil),
            url: authorizeURL(state: "expected"), callbackURLScheme: "scheme",
            presentationContextProvider: provider, prefersEphemeralWebBrowserSession: false)

        await fake.waitUntilStarted()
        // Un state différent ne matche pas → la session reste en vol.
        XCTAssertFalse(store.complete(externalCallbackURL: callback(state: "different")))
        // On termine proprement avec le bon state (sinon l'`await` ci-dessous pendrait).
        XCTAssertTrue(store.complete(externalCallbackURL: callback(state: "expected")))
        _ = try await login
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

    // Chemin d'erreur : si la session se termine en erreur (annulation, échec de présentation…),
    // `run` propage l'erreur ET l'entrée est retirée (defer), donc un callback ultérieur ne matche plus.
    func testEntryIsRemovedWhenRunFails() async {
        let fake = FakeRunner()
        var queue: [FakeRunner] = [fake]
        let store = WebAuthSessionStore(makeSession: { queue.removeFirst() })

        async let login = store.run(
            routing: WebAuthRouting(state: "s", expectedCallback: nil),
            url: authorizeURL(state: "s"), callbackURLScheme: "scheme",
            presentationContextProvider: provider, prefersEphemeralWebBrowserSession: false)

        await fake.waitUntilStarted()
        fake.fail(ReachFiveError.AuthCanceled)

        do {
            _ = try await login
            XCTFail("run doit propager l'erreur de la session")
        } catch { /* attendu */ }

        XCTAssertFalse(store.complete(externalCallbackURL: callback(state: "s")))
    }
}
