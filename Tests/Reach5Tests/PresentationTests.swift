import XCTest
import UIKit
import AuthenticationServices
@testable import Reach5

/// VC conformant au protocole : `webAuthContextProvider()` doit le retourner tel quel
/// pour préserver un anchor choisi par l'app.
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
                return XCTFail("\(message) : attendu TechnicalError, obtenu \(error)")
            }
            XCTAssertTrue(reason.contains(fragment), "\(message) : raison inattendue « \(reason) »")
        }
    }

    // MARK: - presentingViewController

    func testPresentingViewControllerReturnsTheViewController() throws {
        let vc = UIViewController()
        let presentation = Presentation(from: vc)
        XCTAssertIdentical(try presentation.presentingViewController(), vc)
    }

    func testResolversThrowWhenViewControllerIsDeallocated() {
        var vc: UIViewController? = UIViewController()
        let presentation = Presentation(from: vc!)
        vc = nil

        assertThrowsTechnicalError(try presentation.presentingViewController(), reasonContains: "no longer exists",
                                   "presentingViewController après désallocation")
        assertThrowsTechnicalError(try presentation.anchor(), reasonContains: "no longer exists",
                                   "anchor après désallocation")
        assertThrowsTechnicalError(try presentation.webAuthContextProvider(), reasonContains: "no longer exists",
                                   "webAuthContextProvider après désallocation")
    }

    // MARK: - anchor

    func testAnchorThrowsWhenViewControllerIsNotAttachedToAWindow() {
        // Référence forte locale : Presentation ne retient pas le VC (weak).
        let vc = UIViewController()
        let presentation = Presentation(from: vc)
        assertThrowsTechnicalError(try presentation.anchor(), reasonContains: "not attached to a window",
                                   "anchor sans fenêtre")
    }

    func testAnchorReturnsTheWindowWhenAttached() throws {
        let vc = UIViewController()
        let window = UIWindow()
        window.rootViewController = vc
        window.makeKeyAndVisible()

        XCTAssertIdentical(try Presentation(from: vc).anchor(), window)
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

        // La fenêtre est attachée APRÈS la création de l'adaptateur : elle doit
        // quand même être résolue, preuve que la résolution est paresseuse.
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
        XCTAssertNil(weakVC, "l'adaptateur ne doit pas retenir le view controller")
        _ = provider
    }

    func testWebAuthContextProviderAdapterFallsBackSilentlyWhenViewControllerIsDeallocated() throws {
        // Documente le comportement actuel : si le view controller est désalloué entre la
        // création de l'adaptateur et l'appel du callback par ASWebAuthenticationSession,
        // aucune erreur n'est levée (le callback n'est pas throwing) — l'adaptateur retombe
        // silencieusement sur une anchor de repli fraîchement créée plutôt que de signaler l'échec.
        var vc: UIViewController? = UIViewController()
        let provider = try Presentation(from: vc!).webAuthContextProvider()
        weak var weakVC = vc
        vc = nil
        XCTAssertNil(weakVC, "précondition : le view controller doit être réellement désalloué")

        let firstAnchor = provider.presentationAnchor(for: makeSession())
        let secondAnchor = provider.presentationAnchor(for: makeSession())
        XCTAssertNotIdentical(firstAnchor, secondAnchor,
                              "l'anchor de repli doit être reconstruite à chaque appel, pas mise en cache")
    }
}
