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

    public init(reachfive: ReachFive, providerConfig: ProviderConfig) {
        self.reachfive = reachfive
        self.providerConfig = providerConfig
        self.name = providerConfig.provider
    }

    public func login(
        scope: [String]?,
        origin: String,
        viewController: UIViewController?
    ) async throws -> AuthToken {

        guard let presentationContextProvider = viewController as? ASWebAuthenticationPresentationContextProviding else {
            throw ReachFiveError.TechnicalError(reason: "No presenting viewController")
        }

        return try await reachfive.webviewLogin(
            WebviewLoginRequest(
                scope: scope,
                presentationContextProvider: presentationContextProvider,
                origin: origin,
                provider: providerConfig.providerWithVariant,
                // Un provider à universal link (ex. B.connect) termine son flow dans une app externe et
                // rouvre l'app hôte hors-bande via ce universal link, qui EST le redirect_uri OAuth (même
                // valeur pour /authorize et /token). Sinon, scheme custom du SDK.
                callback: providerConfig.universalLink.map { WebviewCallback.externalApp($0) } ?? .sdkScheme))
    }

    override var description: String {
        "Provider: \(providerConfig.provider)"
    }

    public func logout() {
    }
}
