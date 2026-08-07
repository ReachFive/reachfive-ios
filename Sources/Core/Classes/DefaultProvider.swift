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

    // `weak`: ReachFive retains its providers, so a strong reference here would create a
    // ReachFive ↔ DefaultProvider cycle and the SDK graph would never be deallocated (same pattern as
    // LoginWKWebview).
    private weak var reachfive: ReachFive?
    let providerConfig: ProviderConfig
    public let webSessionMode: WebSessionMode?
    /// Why `webSessionMode` is `nil`, reported verbatim by `login()`. `init` has two distinct causes of
    /// failure — no `universalLink` in the backend configuration, or an OS that is too old — and naming only
    /// one of them sends the integrator off to fix a configuration that is already correct.
    private let unavailableModeReason: String?

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
            // A custom scheme needs no `universalLink` from the backend: the redirect_uri is the SdkConfig's.
            webSessionMode = .customScheme
            unavailableModeReason = nil

        case .universalLink:
            // Two causes of deferred failure: the backend configuration carries no `universalLink`, or the OS
            // is too old. `.universalLink` cannot be constructed below iOS 17.4 on the caller's side, but here
            // it is resolved from the backend configuration, hence the runtime check.
            guard let link = providerConfig.universalLink else {
                let reason = "No universal link configured for provider '\(providerConfig.provider)' in universal-link mode"
                Logger.shared.log("\(reason); login() will fail with a TechnicalError.")
                webSessionMode = nil
                unavailableModeReason = reason
                return
            }
            guard #available(iOS 17.4, *) else {
                let reason = "Universal link callback requires iOS 17.4+ (provider '\(providerConfig.provider)')"
                Logger.shared.log("\(reason); login() will fail with a TechnicalError.")
                webSessionMode = nil
                unavailableModeReason = reason
                return
            }
            webSessionMode = .universalLink(link)
            unavailableModeReason = nil
        }
    }

    public func login(
        scope: [String]?,
        origin: String,
        presenting: Presentation
    ) async throws -> AuthToken {

        let presentationContextProvider = try await presenting.webAuthContextProvider()

        guard let webSessionMode else {
            throw ReachFiveError.TechnicalError(reason: unavailableModeReason ?? "No web session mode resolved for provider \(name)")
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
