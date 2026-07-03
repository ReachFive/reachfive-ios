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

    public enum WebProviderMode {
        case sdkScheme
        case externalApp
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

    let reachfive: ReachFive
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
                Logger.shared.log("No universal link configured for \(mode) mode. This will crash at runtime.")
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
