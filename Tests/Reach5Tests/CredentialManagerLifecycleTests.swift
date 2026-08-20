import AuthenticationServices
import XCTest
@testable import Reach5

/// Request lifecycle, driven without any system UI: `perform` runs with an inert submit closure, then the
/// delegate callbacks are simulated by hand.
///
/// The success path is out of reach here: `ASAuthorization` has no public initializer, and the
/// post-processing that follows it makes direct network calls.
@MainActor
final class CredentialManagerLifecycleTests: XCTestCase {
    /// Where `perform`'s submit closure drops the request's controller for the test.
    @MainActor
    private final class ControllerBox {
        var controller: ASAuthorizationController?
    }

    private struct UnexpectedSuccess: Error {}

    /// Keeps every window built by ``makePresentation()`` alive for the duration of the test: `Presentation`
    /// holds the view controller weakly, and the window is what retains it (as its `rootViewController`), so
    /// a test that ignores the returned window would resolve to the fallback anchor instead of its own.
    private var windows: [UIWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

    /// A view controller attached to its own window, so `Presentation` resolves to that very window.
    ///
    /// The window is returned for the tests that assert on the anchor's identity; keeping it alive is
    /// ``windows``' job.
    private func makePresentation() -> (presenting: Presentation, window: UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let viewController = UIViewController()
        // `rootViewController` retains the view controller, and making the window visible is what actually
        // attaches its view: `Presentation` resolves through `viewController.view.window`, which stays nil
        // until then.
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        windows.append(window)
        return (Presentation(from: viewController), window)
    }

    /// Starts an inert request and returns once its context is registered and the request submitted.
    ///
    /// Typed `Task<Void, Error>` rather than `Task<ASAuthorization, Error>`: the authorization is never
    /// inspected, and its `Sendable` conformance — required by a task's `Success` — only exists from
    /// iOS 16.4.
    private func startRequest(on manager: CredentialManager, presenting: Presentation) async throws -> (controller: ASAuthorizationController, result: Task<Void, Error>) {
        let box = ControllerBox()
        let submitted = expectation(description: "request submitted")

        let task = Task { @MainActor in
            _ = try await manager.perform(requests: [ASAuthorizationPasswordProvider().createRequest()], presenting: presenting) {
                box.controller = $0
                submitted.fulfill()
            }
        }

        await fulfillment(of: [submitted], timeout: 1)
        return try (XCTUnwrap(box.controller), task)
    }

    /// Waits for a request to end and returns the error thrown. No test can legitimately succeed: that
    /// would mean a continuation was resumed with a fabricated authorization.
    private func failure(of result: Task<Void, Error>) async throws -> Error {
        do {
            _ = try await result.value
        } catch {
            return error
        }
        XCTFail("the request should have failed")
        throw UnexpectedSuccess()
    }

    func testCanceledRequestThrowsAuthCanceledThenSecondCallbackIsIgnored() async throws {
        let manager = CredentialManager()
        let (controller, result) = try await startRequest(on: manager, presenting: makePresentation().presenting)

        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.canceled))

        let thrown = try await failure(of: result)
        guard case ReachFiveError.AuthCanceled = thrown else {
            return XCTFail("expected .AuthCanceled, got \(thrown)")
        }

        // Context removed on completion, so a second callback is ignored — resuming twice would crash.
        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.failed))
    }

    func testStrayCallbackIsIgnoredAndLeavesLaterRequestsIntact() async throws {
        let manager = CredentialManager()
        let stranger = ASAuthorizationController(authorizationRequests: [ASAuthorizationPasswordProvider().createRequest()])

        // No ongoing request: nothing to resolve, and above all no crash
        manager.authorizationController(controller: stranger, didCompleteWithError: ASAuthorizationError(.canceled))

        let (presenting, window) = makePresentation()
        let (controller, result) = try await startRequest(on: manager, presenting: presenting)
        XCTAssertTrue(manager.presentationAnchor(for: controller) === window)

        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.failed))
        let thrown = try await failure(of: result)
        guard case ReachFiveError.TechnicalError = thrown else {
            return XCTFail("expected .TechnicalError, got \(thrown)")
        }
    }

    /// The refactor's central contract: a new request cancels the ongoing one, and the canceled
    /// request's state disappears without ever touching the new one's.
    func testNewRequestCancelsTheOngoingOneWithoutDisturbingItsOwnState() async throws {
        let manager = CredentialManager()
        let (autoFillPresenting, autoFillWindow) = makePresentation()
        let (modalPresenting, modalWindow) = makePresentation()

        let autoFill = try await startRequest(on: manager, presenting: autoFillPresenting)
        XCTAssertTrue(manager.presentationAnchor(for: autoFill.controller) === autoFillWindow)

        // The modal request cancels the ongoing auto-fill, without waiting for a system callback
        let modal = try await startRequest(on: manager, presenting: modalPresenting)

        let thrown = try await failure(of: autoFill.result)
        guard case ReachFiveError.AuthCanceled = thrown else {
            return XCTFail("expected .AuthCanceled, got \(thrown)")
        }

        XCTAssertFalse(manager.presentationAnchor(for: autoFill.controller) === autoFillWindow)
        XCTAssertTrue(manager.presentationAnchor(for: modal.controller) === modalWindow)

        // The canceled request's late system callback has no effect: the modal stays in the race
        manager.authorizationController(controller: autoFill.controller, didCompleteWithError: ASAuthorizationError(.canceled))

        manager.authorizationController(controller: modal.controller, didCompleteWithError: ASAuthorizationError(.failed))
        let modalThrown = try await failure(of: modal.result)
        guard case ReachFiveError.TechnicalError = modalThrown else {
            return XCTFail("expected .TechnicalError, got \(modalThrown)")
        }
    }

    /// `cancelOngoingRequests` resolves the continuations itself: it does not depend on a
    /// `didCompleteWithError(.canceled)` the system only promises if a flow was really running.
    func testCancelOngoingRequestsResolvesTheRequestWithoutSystemCallback() async throws {
        let manager = CredentialManager()
        let (presenting, window) = makePresentation()
        let (controller, result) = try await startRequest(on: manager, presenting: presenting)

        manager.cancelOngoingRequests()

        let thrown = try await failure(of: result)
        guard case ReachFiveError.AuthCanceled = thrown else {
            return XCTFail("expected .AuthCanceled, got \(thrown)")
        }
        XCTAssertFalse(manager.presentationAnchor(for: controller) === window, "the context should have been released")
    }

    /// A caller that cancels its task (screen dismissed, `async let` abandoned) gets a technical error and
    /// not `.AuthCanceled`, which pushes apps to restart an auto-fill request.
    func testCallerCancellationResumesWithTechnicalErrorAndFreesTheContext() async throws {
        let manager = CredentialManager()
        let (presenting, window) = makePresentation()
        let (controller, result) = try await startRequest(on: manager, presenting: presenting)

        result.cancel()

        let thrown = try await failure(of: result)
        guard case let ReachFiveError.TechnicalError(reason, _) = thrown else {
            return XCTFail("expected .TechnicalError, got \(thrown)")
        }
        XCTAssertTrue(reason.contains("calling task was canceled"))
        XCTAssertFalse(manager.presentationAnchor(for: controller) === window, "the context should have been released")

        // The late system callback finds no context left: no double resumption
        manager.authorizationController(controller: controller, didCompleteWithError: ASAuthorizationError(.canceled))
    }

    func testAlreadyCanceledCallerSubmitsNothing() async throws {
        let manager = CredentialManager()
        let notSubmitted = expectation(description: "no request submitted")
        notSubmitted.isInverted = true

        let task = Task { @MainActor in
            _ = try await manager.perform(requests: [ASAuthorizationPasswordProvider().createRequest()], presenting: makePresentation().presenting) { _ in
                notSubmitted.fulfill()
            }
        }
        // The task is isolated on the main actor, which runs this test: its body has not started yet
        task.cancel()

        let thrown = try await failure(of: task)
        guard case let ReachFiveError.TechnicalError(reason, _) = thrown else {
            return XCTFail("expected .TechnicalError, got \(thrown)")
        }
        XCTAssertTrue(reason.contains("calling task was canceled"))
        await fulfillment(of: [notSubmitted], timeout: 0.2)
    }

    /// Reachable through the public API with `usingModalAuthorizationFor: []`.
    func testEmptyRequestsThrowsInsteadOfHanging() async {
        let manager = CredentialManager()
        do {
            _ = try await manager.perform(requests: [], presenting: makePresentation().presenting) { _ in
                XCTFail("no request should be submitted")
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
