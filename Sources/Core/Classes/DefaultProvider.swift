import Foundation
import AuthenticationServices

/// Registers a **web** provider (one without a native SDK component, served by `DefaultProvider`) so the app
/// can pick its **variant** — exactly like native creators carry a `variant`. The chosen variant flows through
/// the existing mechanism: `ReachFive.reinitialize()` sends `providersCreators.map { ($0.name, $0.variant) }`
/// to `/api/v1/providers`, and the returned per-variant config (incl. `universalLink`) drives `DefaultProvider`.
///
/// Example: `WebProvider(name: .bconnect, variant: "natif")`.
public final class WebProvider: ProviderCreator {
    /// The variant-aware SLO providers the backend exposes a variant for. `rawValue` is the backend name.
    public enum Name: String {
        case apple
        case facebook
        case google
        case line
        case bconnect
    }

    private let providerName: Name
    public var name: String { providerName.rawValue }
    public let variant: String?

    public init(name: Name, variant: String? = nil) {
        self.providerName = name
        self.variant = variant
    }

    public func create(reachFive: ReachFive, providerConfig: ProviderConfig, clientConfigResponse: ClientConfigResponse) -> any Provider {
        DefaultProvider(reachfive: reachFive, providerConfig: providerConfig)
    }
}

class DefaultProvider: NSObject, Provider {
    let name: String

    let reachfive: ReachFive
    let providerConfig: ProviderConfig

    /// Set when the provider ends its flow by redirecting to a **universal link** (https) rather than
    /// the custom scheme — e.g. an external app (a bank doing identity verification) reopens the host
    /// app with the authorization code. That link is delivered by the system via
    /// `application(_:continue:)` while the `ASWebAuthenticationSession` is still open, so we complete
    /// the session out-of-band. (The iOS 17.4 `.https` session callback does NOT help here: it only
    /// intercepts redirects navigated *inside* the session's web view.)
    ///
    /// Requirements on the host app for this case:
    /// - an `applinks:<host>` Associated Domain (+ a matching apple-app-site-association file),
    /// - forwarding `application(_:continue:)` / `scene(_:continue:)` to `ReachFive.application(_:continue:…)`.
    private let universalLink: URL?

    /// The `WebAuthenticationSession` for the login currently in flight. A **fresh** instance is created
    /// per `login()` (its one-shot completion guard must never be reused) and kept here only so an
    /// incoming universal link can complete it out-of-band — see `application(_:continue:)`. The login
    /// orchestration itself (PKCE, authorize URL, code exchange) lives in `ReachFive.webviewLogin`.
    private var webAuthentication: WebAuthenticationSession?

    public init(reachfive: ReachFive, providerConfig: ProviderConfig) {
        self.reachfive = reachfive
        self.providerConfig = providerConfig
        self.name = providerConfig.provider
        self.universalLink = providerConfig.universalLink.flatMap { URL(string: $0) }
    }

    public func login(
        scope: [String]?,
        origin: String,
        viewController: UIViewController?
    ) async throws -> AuthToken {

        guard let presentationContextProvider = viewController as? ASWebAuthenticationPresentationContextProviding else {
            throw ReachFiveError.TechnicalError(reason: "No presenting viewController")
        }

        // A fresh, single-use session per login: never reuse one whose completion guard is already set.
        let webAuthentication = WebAuthenticationSession()
        self.webAuthentication = webAuthentication

        return try await reachfive.webviewLogin(
            WebviewLoginRequest(
                scope: scope,
                presentationContextProvider: presentationContextProvider,
                origin: origin,
                provider: providerConfig.providerWithVariant,
                // For a universal-link provider, the universal link IS the OAuth redirect_uri (same
                // value for /authorize and /token); for others this is nil → custom scheme.
                redirectUri: providerConfig.universalLink
            ),
            using: webAuthentication)
    }

    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let universalLink,
              userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL,
              url.host == universalLink.host,
              url.path.hasPrefix(universalLink.path) else {
            return false
        }
        Task { @MainActor in webAuthentication?.complete(externalCallbackURL: url) }
        return true
    }


    override var description: String {
        "Provider: \(providerConfig.provider)"
    }

    public func logout() {
    }
}
