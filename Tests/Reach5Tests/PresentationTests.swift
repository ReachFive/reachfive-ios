import XCTest
import UIKit
import AuthenticationServices
@testable import Reach5

/// A view controller conforming to the protocol: `webAuthContextProvider()` must return it as-is, so an
/// anchor chosen by the app keeps precedence.
private final class ConformingViewController: UIViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}

@MainActor
final class PresentationTests: XCTestCase {

    private func makeSession() -> ASWebAuthenticationSession {
        ASWebAuthenticationSession(url: URL(string: "https://example.com")!, callbackURLScheme: "test") { _, _ in }
    }

    private func assertThrowsTechnicalError<T>(_ expression: @autoclosure () throws -> T, reasonContains fragment: String, _ message: String) {
        XCTAssertThrowsError(try expression()) { error in
            guard case ReachFiveError.TechnicalError(let reason, _) = error else {
                return XCTFail("\(message): expected a TechnicalError, got \(error)")
            }
            XCTAssertTrue(reason.contains(fragment), "\(message): unexpected reason \"\(reason)\"")
        }
    }

    // MARK: - presentingViewController

    func testPresentingViewControllerReturnsTheViewController() throws {
        let vc = UIViewController()
        let presentation = Presentation(from: vc)
        XCTAssertIdentical(try presentation.presentingViewController(), vc)
    }

    /// Only the two throwing resolvers are listed here: `anchor()` cannot report a failure, see its own
    /// tests below.
    func testThrowingResolversThrowWhenViewControllerIsDeallocated() {
        var vc: UIViewController? = UIViewController()
        let presentation = Presentation(from: vc!)
        vc = nil

        assertThrowsTechnicalError(try presentation.presentingViewController(), reasonContains: "no longer exists",
                                   "presentingViewController after deallocation")
        assertThrowsTechnicalError(try presentation.webAuthContextProvider(), reasonContains: "no longer exists",
                                   "webAuthContextProvider after deallocation")
    }

    // MARK: - anchor

    func testAnchorReturnsTheWindowWhenAttached() {
        let vc = UIViewController()
        let window = UIWindow()
        window.rootViewController = vc
        window.makeKeyAndVisible()

        XCTAssertIdentical(Presentation(from: vc).anchor(), window)
    }

    /// The protocols that ask the SDK for an anchor cannot report a failure, so a view controller with no
    /// window resolves to a fallback anchor instead of an error. There is no key window in the test process,
    /// so the fallback here is a bare detached anchor.
    func testAnchorFallsBackWhenViewControllerIsNotAttachedToAWindow() {
        // Local strong reference: Presentation holds the view controller weakly.
        let vc = UIViewController()
        let presentation = Presentation(from: vc)

        XCTAssertNotIdentical(presentation.anchor(), presentation.anchor(),
                              "the fallback anchor must be rebuilt on each call, not cached")
    }

    func testAnchorFallsBackWhenViewControllerIsDeallocated() {
        var vc: UIViewController? = UIViewController()
        let presentation = Presentation(from: vc!)
        weak var weakVC = vc
        vc = nil
        XCTAssertNil(weakVC, "precondition: the view controller must really be deallocated")

        XCTAssertNotIdentical(presentation.anchor(), presentation.anchor(),
                              "the fallback anchor must be rebuilt on each call, not cached")
    }

    // MARK: - webAuthContextProvider

    func testWebAuthContextProviderReturnsAConformingViewControllerAsIs() throws {
        let vc = ConformingViewController()
        let provider = try Presentation(from: vc).webAuthContextProvider()
        XCTAssertIdentical(provider, vc)
    }

    func testWebAuthContextProviderAdapterResolvesTheWindowLazily() throws {
        let vc = UIViewController()
        let provider = try Presentation(from: vc).webAuthContextProvider()
        XCTAssertNotIdentical(provider, vc)

        // The window is attached AFTER the adapter was built: it must still be resolved, which is what
        // makes the resolution late.
        let window = UIWindow()
        window.rootViewController = vc
        window.makeKeyAndVisible()

        XCTAssertIdentical(provider.presentationAnchor(for: makeSession()), window)
    }

    func testWebAuthContextProviderAdapterDoesNotRetainTheViewController() throws {
        var vc: UIViewController? = UIViewController()
        let provider = try Presentation(from: vc!).webAuthContextProvider()
        weak var weakVC = vc
        vc = nil
        XCTAssertNil(weakVC, "the adapter must not retain the view controller")
        _ = provider
    }

    func testWebAuthContextProviderAdapterFallsBackSilentlyWhenViewControllerIsDeallocated() throws {
        // The adapter delegates to `anchor()`: if the view controller is deallocated between building the
        // adapter and the moment ASWebAuthenticationSession asks for the anchor, no error is raised — the
        // callback is not throwing — and the session gets the same fallback anchor.
        var vc: UIViewController? = UIViewController()
        let provider = try Presentation(from: vc!).webAuthContextProvider()
        weak var weakVC = vc
        vc = nil
        XCTAssertNil(weakVC, "precondition: the view controller must really be deallocated")

        let firstAnchor = provider.presentationAnchor(for: makeSession())
        let secondAnchor = provider.presentationAnchor(for: makeSession())
        XCTAssertNotIdentical(firstAnchor, secondAnchor,
                              "the fallback anchor must be rebuilt on each call, not cached")
    }

    // MARK: - Request convenience inits

    func testWebviewLoginRequestConvenienceInitDerivesTheContextProvider() throws {
        let vc = ConformingViewController()
        let request = try WebviewLoginRequest(presenting: Presentation(from: vc))
        XCTAssertIdentical(request.presentationContextProvider, vc)
    }

    func testWebSessionLogoutRequestConvenienceInitDerivesTheContextProvider() throws {
        let vc = ConformingViewController()
        let request = try WebSessionLogoutRequest(presenting: Presentation(from: vc))
        XCTAssertIdentical(request.presentationContextProvider, vc)
    }
}
