import AuthenticationServices
@testable import Reach5

/// Fournisseur de contexte factice pour les tests qui construisent une `WebviewLoginRequest`
/// sans présenter de session (la méthode n'est jamais appelée, faute de session présentée).
final class DummyContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        fatalError("DummyContextProvider.presentationAnchor ne doit pas être appelé en test")
    }
}
