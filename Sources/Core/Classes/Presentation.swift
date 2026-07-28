import UIKit
import AuthenticationServices

/// Where provider UI (authentication sheets, sign-in dialogs) is presented from.
///
/// Create it from the view controller initiating the login, once it is attached to a window
/// (i.e. from `viewDidAppear` or a user interaction, not from `viewDidLoad`):
///
/// ```swift
/// try await provider.login(scope: scope, origin: origin, presenting: Presentation(from: self))
/// ```
///
/// Each provider derives from it the exact form its underlying API needs — the view controller
/// itself, its window, or an `ASWebAuthenticationSession` context provider. The view controller
/// is held weakly: `Presentation` never retains it.
@MainActor
public struct Presentation {
    private weak var viewController: UIViewController?

    public init(from viewController: UIViewController) {
        self.viewController = viewController
    }

    /// The view controller to present from (e.g. Google Sign-In dialogs).
    ///
    /// - Throws: `ReachFiveError.TechnicalError` if the view controller has been deallocated.
    public func presentingViewController() throws -> UIViewController {
        guard let viewController else {
            throw ReachFiveError.TechnicalError(reason: "The presenting view controller no longer exists")
        }
        return viewController
    }

    /// The window the view controller is attached to (Sign In with Apple, passkeys).
    ///
    /// - Throws: `ReachFiveError.TechnicalError` if the view controller has been deallocated
    ///   or is not attached to a window. Call `login()` after the view appeared
    ///   (e.g. from `viewDidAppear`), not from `viewDidLoad`.
    public func anchor() throws -> ASPresentationAnchor {
        guard let window = try presentingViewController().view.window else {
            throw ReachFiveError.TechnicalError(reason: "The presenting view controller is not attached to a window. Call login() after the view appeared (e.g. from viewDidAppear), not from viewDidLoad.")
        }
        return window
    }

    /// A context provider for `ASWebAuthenticationSession` (web providers).
    ///
    /// If the view controller conforms to `ASWebAuthenticationPresentationContextProviding`
    /// it is returned as-is, so an anchor chosen by the app keeps precedence. Otherwise an
    /// SDK adapter resolving the view controller's window on demand is returned.
    ///
    /// - Throws: `ReachFiveError.TechnicalError` if the view controller has been deallocated.
    public func webAuthContextProvider() throws -> ASWebAuthenticationPresentationContextProviding {
        let viewController = try presentingViewController()
        if let contextProvider = viewController as? ASWebAuthenticationPresentationContextProviding {
            return contextProvider
        }
        return ViewControllerContextProvider(viewController)
    }
}

// `ASWebAuthenticationSession.presentationContextProvider` est `weak` : l'adaptateur doit être
// retenu ailleurs pendant la session. C'est le cas via `WebviewLoginRequest.presentationContextProvider`
// (`let` fort), vivant pendant tout `webviewLogin` → `webAuthSession.start(...)`.
private final class ViewControllerContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private weak var viewController: UIViewController?

    init(_ viewController: UIViewController) {
        self.viewController = viewController
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        viewController?.view.window ?? ASPresentationAnchor()
    }
}
