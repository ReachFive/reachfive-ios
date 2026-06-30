import XCTest
import AuthenticationServices
@testable import Reach5

@MainActor
final class WebAuthSessionHolderTests: XCTestCase {

    private let provider = DummyContextProvider()
    private let expected = URL(string: "https://host.example.com/cb")!
    private let authorizeURL = URL(string: "https://r5.example.com/authorize")!

    private func callback(code: String = "c") -> URL {
        URL(string: "https://host.example.com/cb?code=\(code)")!
    }

    private func holder(_ fakes: FakeRunner...) -> WebAuthSessionHolder {
        var queue = Array(fakes)
        return WebAuthSessionHolder(makeSession: { queue.removeFirst() })
    }

    // Aucune session en vol → le lien n'est pas consommé (#1).
    func testCompleteReturnsFalseWhenNoSessionInFlight() {
        let store = WebAuthSessionHolder(makeSession: { FakeRunner() })
        XCTAssertFalse(store.complete(externalCallbackURL: callback()))
    }

    // Un callback de la bonne forme complète la session en cours et `run` en retourne l'URL.
    func testCompletesInFlightSessionOnMatchingCallback() async throws {
        let fake = FakeRunner()
        let store = holder(fake)

        async let login = store.run(url: authorizeURL, expectedCallback: expected, callbackURLScheme: "scheme",
                                     presentationContextProvider: provider, prefersEphemeralWebBrowserSession: false)
        await fake.waitUntilStarted()
        XCTAssertTrue(store.complete(externalCallbackURL: callback(code: "xyz")))

        let result = try await login
        XCTAssertEqual(result, callback(code: "xyz"))
    }

    // Un lien qui n'est pas notre callback renvoie false et ne complète pas la session (#1).
    func testNonMatchingCallbackReturnsFalseAndLeavesSessionPending() async throws {
        let fake = FakeRunner()
        let store = holder(fake)

        async let login = store.run(url: authorizeURL, expectedCallback: expected, callbackURLScheme: "scheme",
                                     presentationContextProvider: provider, prefersEphemeralWebBrowserSession: false)
        await fake.waitUntilStarted()
        // Mauvais host → pas notre callback ; la session reste en vol.
        XCTAssertFalse(store.complete(externalCallbackURL: URL(string: "https://other.example.com/cb?code=c")!))
        // On termine proprement.
        XCTAssertTrue(store.complete(externalCallbackURL: callback()))
        _ = try await login
    }

    // Idempotence : une fois la session terminée, la fente est vide → un second callback n'est plus consommé.
    func testCompleteIsFalseAfterSessionFinished() async throws {
        let fake = FakeRunner()
        let store = holder(fake)

        async let login = store.run(url: authorizeURL, expectedCallback: expected, callbackURLScheme: "scheme",
                                     presentationContextProvider: provider, prefersEphemeralWebBrowserSession: false)
        await fake.waitUntilStarted()
        XCTAssertTrue(store.complete(externalCallbackURL: callback()))
        _ = try await login

        XCTAssertFalse(store.complete(externalCallbackURL: callback()))
    }

    // Chemin d'erreur : si la session échoue, `run` propage l'erreur et la fente est vidée.
    func testSlotClearedWhenRunFails() async {
        let fake = FakeRunner()
        let store = holder(fake)

        async let login = store.run(url: authorizeURL, expectedCallback: expected, callbackURLScheme: "scheme",
                                    presentationContextProvider: provider, prefersEphemeralWebBrowserSession: false)
        await fake.waitUntilStarted()
        fake.fail(ReachFiveError.AuthCanceled)

        do {
            _ = try await login
            XCTFail("run doit propager l'erreur de la session")
        } catch { /* attendu */ }

        XCTAssertFalse(store.complete(externalCallbackURL: callback()))
    }

    // Sans expectedCallback (login par scheme custom), aucun universal link n'est consommé hors-bande.
    func testNoExpectedCallbackNeverMatches() async throws {
        let fake = FakeRunner()
        let store = holder(fake)

        async let login = store.run(url: authorizeURL, expectedCallback: nil, callbackURLScheme: "scheme",
                                     presentationContextProvider: provider, prefersEphemeralWebBrowserSession: false)
        await fake.waitUntilStarted()
        XCTAssertFalse(store.complete(externalCallbackURL: callback()))
        // On termine via le runner (comme le ferait le callback de scheme in-band).
        fake.complete(externalCallbackURL: callback())
        _ = try await login
    }
}
