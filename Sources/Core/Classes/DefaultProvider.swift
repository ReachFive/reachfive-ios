import Foundation
import AuthenticationServices

/// Registers a **web** provider (one without a native SDK component, served by `DefaultProvider`) so the app
/// can pick its **variant** and its **completion mode**
///
/// Example: `WebProvider(name: .bconnect, variant: "natif", mode: .externalAppUniversalLink)`.
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

    /// Selects how the `ASWebAuthenticationSession` should complete for this provider, on the same two
    /// orthogonal axes as ``WebSessionMode`` — the callback shape (custom scheme vs universal link) and the
    /// channel (in-band vs out-of-band) — but without any URL: for a universal-link callback the SDK reads
    /// the provider's `universalLink` from its backend config. `DefaultProvider.init` resolves this into the
    /// corresponding ``WebSessionMode``. Exposed as named factories (private init); the in-sheet universal
    /// link is annotated `@available(iOS 17.4, *)`.
    public struct WebProviderMode {
        enum Callback { case customScheme, universalLink }
        let callback: Callback
        let channel: WebSessionMode.Channel

        private init(callback: Callback, channel: WebSessionMode.Channel) {
            self.callback = callback
            self.channel = channel
        }

        /// Custom scheme intercepted _inside_ the sheet — the default, on every iOS version.
        public static let sdkScheme = WebProviderMode(callback: .customScheme, channel: .inBand)

        /// out-of-band: an external app reopens the host app via the custom scheme (`application(_:open:)`).
        public static let externalAppScheme = WebProviderMode(callback: .customScheme, channel: .outOfBand)

        /// out-of-band: an external app reopens the host app via a universal link (`application(_:continue:)`).
        /// Requires the `applinks:<host>` Associated Domain on the host app side.
        public static let externalAppUniversalLink = WebProviderMode(callback: .universalLink, channel: .outOfBand)

        /// Universal link intercepted _inside_ the webview (iOS 17.4+ via `callback: .https`). Requires the
        /// `webcredentials:<host>` Associated Domain. Reserve for flows that stay within the sheet.
        @available(iOS 17.4, *)
        public static let inSheetUniversalLink = WebProviderMode(callback: .universalLink, channel: .inBand)
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

        switch mode.callback {
        case .customScheme:
            // Le custom scheme n'a pas besoin de l'`universalLink` du backend : la redirect_uri est celle
            // du SdkConfig, in-band comme hors-bande.
            webSessionMode = mode.channel == .inBand ? .sdkScheme : .externalAppScheme

        case .universalLink:
            guard let link = providerConfig.universalLink else {
                Logger.shared.log("No universal link configured for provider '\(providerConfig.provider)' in universal-link mode; login() will fail with a TechnicalError.")
                webSessionMode = nil
                return
            }
            if mode.channel == .inBand {
                guard #available(iOS 17.4, *) else {
                    Logger.shared.log("In-sheet universal link requires iOS 17.4+; login() for provider '\(providerConfig.provider)' will fail with a TechnicalError.")
                    webSessionMode = nil
                    return
                }
                webSessionMode = .inSheetUniversalLink(link)
            } else {
                webSessionMode = .externalAppUniversalLink(link)
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
