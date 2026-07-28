import Foundation
import AuthenticationServices

/// Registers a **web** provider (one without a native SDK component, served by `DefaultProvider`) so the app
/// can pick its **variant** and its **completion mode**
///
/// Example: `WebProvider(name: .bconnect, variant: "natif", mode: .customScheme)`.
public final class WebProvider: ProviderCreator {
    /// The SLO providers supported by the backend. `rawValue` is the backend name.
    public enum Name: String {
        case facebook
        case google
        case payPal = "paypal"
        case twitter
        case franceConnect = "franceconnect"
        case oney
        case bconnect
        case line
    }

    /// How this provider's login session completes. Same choices as ``WebSessionMode``, resolved into it by
    /// `DefaultProvider.init` (`universalLink` uses the provider's `universalLink` from its backend config).
    public enum WebProviderMode {
        /// Custom scheme — the default, on every iOS version. Covers both a redirection intercepted in
        /// the sheet and one delivered by the default browser to `application(_:open:)`.
        case customScheme

        /// Universal link intercepted in the sheet (via `callback: .https`).
        @available(iOS 17.4, *)
        case universalLink
    }

    private let providerName: Name
    public var name: String { providerName.rawValue }
    public let variant: String?
    public let mode: WebProviderMode

    public init(name: Name, variant: String? = nil, mode: WebProviderMode = .customScheme) {
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
        mode: WebProvider.WebProviderMode = .customScheme
    ) {
        self.reachfive = reachfive
        self.providerConfig = providerConfig
        self.name = providerConfig.provider

        switch mode {
        case .customScheme:
            // Le custom scheme n'a pas besoin de l'`universalLink` du backend : la redirect_uri est celle
            // du SdkConfig.
            webSessionMode = .customScheme

        case .universalLink:
            // Deux causes d'échec différé : la configuration backend ne porte pas d'`universalLink`, ou
            // l'OS est trop ancien. Le cas `.universalLink` est inconstructible sous iOS 17.4 côté
            // appelant, mais il est ici résolu depuis la configuration backend — contrôle runtime.
            guard let link = providerConfig.universalLink else {
                Logger.shared.log("No universal link configured for provider '\(providerConfig.provider)' in universal-link mode; login() will fail with a TechnicalError.")
                webSessionMode = nil
                return
            }
            guard #available(iOS 17.4, *) else {
                Logger.shared.log("Universal link callback requires iOS 17.4+; login() for provider '\(providerConfig.provider)' will fail with a TechnicalError.")
                webSessionMode = nil
                return
            }
            webSessionMode = .universalLink(link)
        }
    }

    public func login(
        scope: [String]?,
        origin: String,
        presenting: Presentation
    ) async throws -> AuthToken {

        let presentationContextProvider = try await presenting.webAuthContextProvider()

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
