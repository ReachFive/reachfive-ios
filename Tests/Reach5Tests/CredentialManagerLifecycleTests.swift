import AuthenticationServices
import XCTest
@testable import Reach5

/// Le cycle de vie des requêtes, piloté sans UI système : `perform` est lancée avec une closure de
/// soumission inerte (la requête n'est jamais soumise au système), puis les callbacks du delegate sont
/// simulés à la main.
///
/// Couvert ici : une continuation par requête, reprise exactement une fois, sur tous les chemins d'échec
/// (annulation utilisateur, erreur technique, annulation par une nouvelle requête, annulation de la tâche
/// appelante, requête vide), et l'isolation de l'état entre une requête annulée et celle qui la remplace.
///
/// Non couvert, et pas couvrable ici : le chemin de succès. `ASAuthorization` n'a pas d'initialiseur
/// public, il est donc impossible de fabriquer une autorisation de test ; et le post-traitement qui la
/// suit dans chaque point d'entrée fait des appels réseau directs, `ReachFiveApi` n'étant pas abstrait
/// derrière un protocole.
@MainActor
final class CredentialManagerLifecycleTests: XCTestCase {
    /// La closure de soumission de `perform` y dépose le controller de la requête pour le test.
    @MainActor
    private final class ControllerBox {
        var controller: ASAuthorizationController?
    }

    private struct UnexpectedSuccess: Error {}

    /// Démarre une requête inerte et rend la main une fois le contexte enregistré et la requête soumise.
    ///
    /// La tâche est typée `Task<Void, Error>` et non `Task<ASAuthorization, Error>` : l'autorisation n'est
    /// jamais inspectée (elle n'est pas fabricable en test) et la conformité de `ASAuthorization` à
    /// `Sendable`, exigée par le paramètre `Success` d'une tâche, n'existe qu'à partir d'iOS 16.4.
    private func startRequest(on manager: CredentialManager, anchor: ASPresentationAnchor) async throws -> (controller: ASAuthorizationController, result: Task<Void, Error>) {
        let box = ControllerBox()
        let submitted = expectation(description: "requête soumise")

        let task = Task { @MainActor in
            _ = try await manager.perform(requests: [ASAuthorizationPasswordProvider().createRequest()], anchor: anchor) {
                box.controller = $0
                submitted.fulfill()
            }
        }

        await fulfillment(of: [submitted], timeout: 1)
        return try (XCTUnwrap(box.controller), task)
    }

    /// Attend la fin d'une requête et rend l'erreur levée. Aucun test ne peut légitimement aboutir : une
    /// reprise en succès signifierait qu'une continuation a été résolue avec une autorisation fabriquée.
    private func failure(of result: Task<Void, Error>) async throws -> Error {
        do {
            _ = try await result.value
        } catch {
            return error
        }
        XCTFail("la requête devait échouer")
        throw UnexpectedSuccess()
    }

    func testCanceledRequestThrowsAuthCanceledThenSecondCallbackIsIgnored() async throws {
        let manager = CredentialManager()
        let (controller, result) = try await startRequest(on: manager, anchor: ASPresentationAnchor())

        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.canceled))

        let thrown = try await failure(of: result)
        guard case ReachFiveError.AuthCanceled = thrown else {
            return XCTFail("expected .AuthCanceled, got \(thrown)")
        }

        // Le contexte a été retiré à la complétion : un second callback pour le même controller est ignoré
        // (une continuation reprise deux fois ferait crasher le test).
        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.failed))
    }

    func testStrayCallbackIsIgnoredAndLeavesLaterRequestsIntact() async throws {
        let manager = CredentialManager()
        let stranger = ASAuthorizationController(authorizationRequests: [ASAuthorizationPasswordProvider().createRequest()])

        // Aucune requête en cours : rien à résoudre, et surtout pas de crash
        manager.authorizationController(controller: stranger, didCompleteWithError: ASAuthorizationError(.canceled))

        // Le dictionnaire de contextes n'a pas été corrompu : une vraie requête se déroule normalement
        let anchor = ASPresentationAnchor()
        let (controller, result) = try await startRequest(on: manager, anchor: anchor)
        XCTAssertTrue(manager.presentationAnchor(for: controller) === anchor)

        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.failed))
        let thrown = try await failure(of: result)
        guard case ReachFiveError.TechnicalError = thrown else {
            return XCTFail("expected .TechnicalError, got \(thrown)")
        }
    }

    /// Le contrat central du refactor : une nouvelle requête annule celle en cours, et l'état de la
    /// requête annulée disparaît sans jamais toucher à celui de la nouvelle.
    func testNewRequestCancelsTheInFlightOneWithoutDisturbingItsOwnState() async throws {
        let manager = CredentialManager()
        let autoFillAnchor = ASPresentationAnchor()
        let modalAnchor = ASPresentationAnchor()

        let autoFill = try await startRequest(on: manager, anchor: autoFillAnchor)
        XCTAssertTrue(manager.presentationAnchor(for: autoFill.controller) === autoFillAnchor)

        // La requête modale annule l'auto-fill en cours, sans attendre de callback système
        let modal = try await startRequest(on: manager, anchor: modalAnchor)

        let thrown = try await failure(of: autoFill.result)
        guard case ReachFiveError.AuthCanceled = thrown else {
            return XCTFail("expected .AuthCanceled, got \(thrown)")
        }

        // L'état de la requête annulée a disparu, celui de la nouvelle est intact
        XCTAssertFalse(manager.presentationAnchor(for: autoFill.controller) === autoFillAnchor)
        XCTAssertTrue(manager.presentationAnchor(for: modal.controller) === modalAnchor)

        // Le callback système tardif de la requête annulée n'a aucun effet : la modale reste en course
        manager.authorizationController(controller: autoFill.controller, didCompleteWithError: ASAuthorizationError(.canceled))

        manager.authorizationController(controller: modal.controller, didCompleteWithError: ASAuthorizationError(.failed))
        let modalThrown = try await failure(of: modal.result)
        guard case ReachFiveError.TechnicalError = modalThrown else {
            return XCTFail("expected .TechnicalError, got \(modalThrown)")
        }
    }

    /// `cancelInFlightRequests` résout elle-même les continuations : elle ne dépend pas d'un
    /// `didCompleteWithError(.canceled)` que le système ne promet que si un flux tournait vraiment.
    func testCancelInFlightRequestsResolvesTheRequestWithoutSystemCallback() async throws {
        let manager = CredentialManager()
        let anchor = ASPresentationAnchor()
        let (controller, result) = try await startRequest(on: manager, anchor: anchor)

        manager.cancelInFlightRequests()

        let thrown = try await failure(of: result)
        guard case ReachFiveError.AuthCanceled = thrown else {
            return XCTFail("expected .AuthCanceled, got \(thrown)")
        }
        XCTAssertFalse(manager.presentationAnchor(for: controller) === anchor, "le contexte doit avoir été libéré")
    }

    /// L'appelant qui annule sa tâche (écran quitté, `async let` abandonné) reçoit `CancellationError` et
    /// non `.AuthCanceled` : cette dernière pousse les applications à relancer une requête auto-fill.
    func testCallerCancellationResumesWithCancellationErrorAndFreesTheContext() async throws {
        let manager = CredentialManager()
        let anchor = ASPresentationAnchor()
        let (controller, result) = try await startRequest(on: manager, anchor: anchor)

        result.cancel()

        let thrown = try await failure(of: result)
        XCTAssertTrue(thrown is CancellationError, "expected CancellationError, got \(thrown)")
        XCTAssertFalse(manager.presentationAnchor(for: controller) === anchor, "le contexte doit avoir été libéré")

        // Le callback système tardif ne trouve plus de contexte : pas de double reprise
        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.canceled))
    }

    func testAlreadyCanceledCallerSubmitsNothing() async throws {
        let manager = CredentialManager()
        let notSubmitted = expectation(description: "aucune requête soumise")
        notSubmitted.isInverted = true

        let task = Task { @MainActor in
            _ = try await manager.perform(requests: [ASAuthorizationPasswordProvider().createRequest()], anchor: ASPresentationAnchor()) { _ in
                notSubmitted.fulfill()
            }
        }
        // La tâche est isolée sur le main actor, qui exécute ce test : son corps n'a pas encore démarré
        task.cancel()

        let thrown = try await failure(of: task)
        XCTAssertTrue(thrown is CancellationError, "expected CancellationError, got \(thrown)")
        await fulfillment(of: [notSubmitted], timeout: 0.2)
    }

    /// `ASAuthorizationController` exige au moins une requête ; sans garde, le système ne rappellerait
    /// jamais le delegate et l'appelant resterait suspendu. Atteignable via l'API publique avec
    /// `usingModalAuthorizationFor: []`.
    func testEmptyRequestsThrowsInsteadOfHanging() async {
        let manager = CredentialManager()
        do {
            _ = try await manager.perform(requests: [], anchor: ASPresentationAnchor()) { _ in
                XCTFail("aucune requête ne doit être soumise")
            }
            XCTFail("expected a .TechnicalError")
        } catch {
            guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
            XCTAssertTrue(reason.contains("No authorization request"))
        }
    }
}
