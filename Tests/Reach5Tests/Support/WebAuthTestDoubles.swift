import AuthenticationServices
@testable import Reach5

/// Faux runner de session web : ne présente aucune `ASWebAuthenticationSession`. Il suspend `start`
/// sur une continuation que le test résout via `complete(externalCallbackURL:)` ou via le store.
/// Permet de tester le routage/sélection du `WebAuthSessionStore` sans UI.
@MainActor
final class FakeRunner: WebAuthRunning {
    private var resultContinuation: CheckedContinuation<URL, Error>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private(set) var didStart = false

    func start(url: URL,
               routing: WebAuthRouting,
               callbackURLScheme: String,
               presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
               prefersEphemeralWebBrowserSession: Bool) async throws -> URL {
        // `didStart` et le signal de démarrage sont posés à l'entrée de `start`, pas dans la
        // continuation : ils représentent « start a été appelé », indépendamment du mécanisme de
        // continuation. Seule la `resultContinuation` doit être capturée dans la closure.
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
        return try await withCheckedThrowingContinuation { self.resultContinuation = $0 }
    }

    /// Suspend jusqu'à ce que `start` ait été appelé (donc la session enregistrée dans le store).
    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { self.startedContinuation = $0 }
    }

    func complete(externalCallbackURL url: URL) {
        resultContinuation?.resume(returning: url)
        resultContinuation = nil
    }
}

/// Fournisseur de contexte factice : jamais sollicité par `FakeRunner` (aucune session présentée).
final class DummyContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        fatalError("DummyContextProvider.presentationAnchor ne doit pas être appelé en test")
    }
}
