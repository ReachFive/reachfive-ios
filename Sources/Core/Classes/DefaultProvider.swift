import Foundation
import AuthenticationServices

/// Registers a **web** provider (one without a native SDK component, served by `DefaultProvider`) so the app
/// can pick its **variant** and its **completion mode**
///
/// Example: `WebProvider(name: .bconnect, variant: "natif", mode: .externalApp)`.
public final class WebProvider: ProviderCreator {
    /// The SLO providers supported by the backend. `rawValue` is the backend name.
    public enum Name: String {
        case Facebook = "facebook"
        case Google = "google"
        case PayPal = "paypal"
        case Twitter = "twitter"
        case FranceConnect = "franceconnect"
        case Oney = "oney"
        case Bconnect = "bconnect"
        case Line = "line"
    }

    /// Selects how the `ASWebAuthenticationSession` should complete for this provider; resolved into the
    /// corresponding ``WebSessionMode`` (with its URL) by `DefaultProvider.init`.
    public enum WebProviderMode {
        /// Custom scheme intercepted by the session (works on all iOS versions). E.g. `reachfive-<clientId>`.
        case sdkScheme

        /// out-of-band completion: the flow ends in an external app that reopens the host app via a
        /// universal link. Requires the `applinks:<host>` Associated Domain on the host app side.
        case externalApp

        /// Universal link intercepted _inside_ the webview (iOS 17.4+ via `callback: .https`). Requires
        /// the `webcredentials:<host>` Associated Domain. Reserve for flows that end
        /// entirely within the sheet (no jump to an external app).
        @available(iOS 17.4, *)
        case universalLink
    }

    private let providerName: Name
    public var name: String { providerName.rawValue }
    public let variant: String?
    public let mode: WebProviderMode

    public init(name: Name, variant: String? = nil, mode: WebProviderMode = .sdkScheme) {
        self.providerName = name
        self.variant = variant
        self.mode = mode
    }

    public func create(reachFive: ReachFive, providerConfig: ProviderConfig, clientConfigResponse: ClientConfigResponse) -> Provider {
        DefaultProvider(reachfive: reachFive, providerConfig: providerConfig, mode: mode)
    }
}

class DefaultProvider: NSObject, Provider {
    let name: String

    // `weak` : ReachFive retient ses providers, une référence forte ici créerait un cycle
    // ReachFive ↔ DefaultProvider et le graphe SDK ne serait jamais désalloué (même pattern que
    // LoginWKWebview).
    private weak var reachfive: ReachFive?
    let providerConfig: ProviderConfig
    public let webSessionMode: WebSessionMode?

    public init(
        reachfive: ReachFive,
        providerConfig: ProviderConfig,
        mode: WebProvider.WebProviderMode = .sdkScheme
    ) {
        self.reachfive = reachfive
        self.providerConfig = providerConfig
        self.name = providerConfig.provider

        if mode == .sdkScheme {
            webSessionMode = .sdkScheme
        } else {
            guard let link = providerConfig.universalLink else {
                Logger.shared.log("No universal link configured for provider '\(providerConfig.provider)' in \(mode) mode; login() will fail with a TechnicalError.")
                webSessionMode = nil
                return
            }
            if mode == .externalApp {
                webSessionMode = WebSessionMode.externalApp(link)
            } else {
                webSessionMode = WebSessionMode.universalLink(link)
            }
        }
    }

    public func login(
        scope: [String]?,
        origin: String,
        viewController: UIViewController?
    ) async throws -> AuthToken {

        guard let presentationContextProvider = viewController as? ASWebAuthenticationPresentationContextProviding else {
            throw ReachFiveError.TechnicalError(reason: "No presenting viewController")
        }

        guard let webSessionMode else {
            throw ReachFiveError.TechnicalError(reason: "No universal link configured for provider \(name)")
        }

        guard let reachfive else {
            throw ReachFiveError.TechnicalError(reason: "ReachFive instance was deallocated")
        }

        return try await reachfive.webviewLogin(
            WebviewLoginRequest(
                scope: scope,
                presentationContextProvider: presentationContextProvider,
                origin: origin,
                provider: providerConfig.providerWithVariant,
                webSessionMode: webSessionMode)
        )
    }

    override var description: String {
        "Provider: \(providerConfig.provider)"
    }

    public func logout() {
    }
}
