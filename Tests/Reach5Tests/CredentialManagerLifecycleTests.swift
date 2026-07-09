import XCTest
import AuthenticationServices
@testable import Reach5

/// Le cycle de vie des requêtes, piloté sans UI système : la méthode générique `perform` est lancée
/// avec une closure `using` inerte (la requête n'est jamais soumise au système), puis les callbacks
/// du delegate sont simulés à la main. C'est le contrat central du refactor : une continuation par
/// requête, résolue exactement une fois, sans interférence entre requêtes entrelacées.
@MainActor
final class CredentialManagerLifecycleTests: XCTestCase {

    private func makeReachFive() -> ReachFive {
        ReachFive(sdkConfig: SdkConfig(domain: "example.reach5.net", clientId: "testclient"))
    }

    /// Démarre une requête `authToken` inerte et rend la main une fois le contexte enregistré.
    private func startRequest(on manager: CredentialManager, anchor: ASPresentationAnchor = ASPresentationAnchor()) async -> (controller: ASAuthorizationController, result: Task<AuthToken, Error>) {
        var controller: ASAuthorizationController?
        let task = Task { @MainActor in
            try await manager.perform(
                CredentialManager.RequestContext.Pending.authToken,
                requests: [ASAuthorizationPasswordProvider().createRequest()],
                reachFive: makeReachFive(),
                anchor: anchor,
                scopes: nil,
                originR5: nil
            ) { controller = $0 }
        }
        // perform s'exécute sur le main actor : céder la main jusqu'à ce que le contexte soit en place
        while controller == nil {
            await Task.yield()
        }
        return (controller!, task)
    }

    func testCanceledRequestThrowsAuthCanceledThenSecondCallbackIsIgnored() async {
        let manager = CredentialManager()
        let (controller, result) = await startRequest(on: manager)

        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.canceled))

        do {
            _ = try await result.value
            XCTFail("expected .AuthCanceled")
        } catch {
            guard case ReachFiveError.AuthCanceled = error else {
                return XCTFail("expected .AuthCanceled, got \(error)")
            }
        }

        // Le contexte a été retiré à la complétion : un second callback pour le même controller
        // est ignoré (une continuation reprise deux fois ferait crasher le test).
        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.failed))
    }

    func testCallbackForUnknownControllerIsIgnored() {
        let manager = CredentialManager()
        let stranger = ASAuthorizationController(authorizationRequests: [ASAuthorizationPasswordProvider().createRequest()])

        // Aucune requête en cours : rien à résoudre, et surtout pas de crash
        manager.authorizationController(controller: stranger, didCompleteWithError: ASAuthorizationError(.canceled))
    }

    func testInterleavedRequestsFailIndependently() async {
        let manager = CredentialManager()
        let first = await startRequest(on: manager)
        let second = await startRequest(on: manager)

        manager.authorizationController(controller: first.controller, didCompleteWithError: ASAuthorizationError(.canceled))

        do {
            _ = try await first.result.value
            XCTFail("expected .AuthCanceled")
        } catch {
            guard case ReachFiveError.AuthCanceled = error else {
                return XCTFail("expected .AuthCanceled, got \(error)")
            }
        }

        // La seconde requête est restée en cours et se résout indépendamment, avec sa propre erreur
        manager.authorizationController(controller: second.controller, didCompleteWithError: ASAuthorizationError(.failed))

        do {
            _ = try await second.result.value
            XCTFail("expected .TechnicalError")
        } catch {
            guard case ReachFiveError.TechnicalError = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
        }
    }

    func testPresentationAnchorIsTheOneOfTheRequest() async {
        let manager = CredentialManager()
        let anchor = ASPresentationAnchor()
        let (controller, result) = await startRequest(on: manager, anchor: anchor)

        XCTAssertTrue(manager.presentationAnchor(for: controller) === anchor)

        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.canceled))
        _ = try? await result.value
    }
}
