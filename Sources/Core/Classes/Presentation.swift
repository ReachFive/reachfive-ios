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

// `ASWebAuthenticationSession.presentationContextProvider` is `weak`, so the adapter has to be retained
// elsewhere for the duration of the session. It is, through
// `WebviewLoginRequest.presentationContextProvider` (a strong `let`), which stays alive for the whole
// `webviewLogin` → `webAuthSession.start(...)` call.
private final class ViewControllerContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private weak var viewController: UIViewController?

    init(_ viewController: UIViewController) {
        self.viewController = viewController
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = viewController?.view.window {
            return window
        }
        // The presenting view controller is gone — deallocated, or dismissed since the request was built
        // (`WebviewLoginRequest.init(presenting:)` resolves this provider at construction time, the session
        // asks for the anchor later). The protocol offers no way to fail, and a bare `ASPresentationAnchor()`
        // belongs to no scene, so the system would always answer `presentationContextInvalid`. Falling back
        // to the app's own key window lets the login go through, anchored elsewhere.
        if let window = Self.activeSceneKeyWindow() {
            Logger.shared.log("The presenting view controller is no longer attached to a window; anchoring the web session on the app's key window instead. Call login() after the view appeared (e.g. from viewDidAppear), not from viewDidLoad.")
            return window
        }
        Logger.shared.log("No window available to anchor the web session: it will fail with presentationContextInvalid. Call login() after the view appeared (e.g. from viewDidAppear), not from viewDidLoad.")
        return ASPresentationAnchor()
    }

    /// The key window of a foreground scene, if there is one.
    ///
    /// There is no app-level shortcut for this on purpose: `UIApplication.keyWindow` is deprecated since
    /// iOS 13 ("returns a key window across all connected scenes"), and the standard replacement,
    /// `UIWindowScene.keyWindow`, is per-scene and iOS 15+. Picking the relevant scene is the app's call, so
    /// it has to be spelled out here — and scanning `windows` for `isKeyWindow` gives the same result while
    /// staying on the iOS 13 floor this package targets.
    private static func activeSceneKeyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // Prefer a foreground-active scene, but accept a foreground-inactive one: a programmatic login or
        // logout can run while the app is still being brought back to the foreground — which is exactly the
        // situation a return from a third-party app creates.
        let candidates = scenes.filter { $0.activationState == .foregroundActive }
            + scenes.filter { $0.activationState == .foregroundInactive }
        return candidates.flatMap(\.windows).first(where: \.isKeyWindow)
    }
}
