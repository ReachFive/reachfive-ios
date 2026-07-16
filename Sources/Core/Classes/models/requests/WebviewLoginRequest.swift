import Foundation
import AuthenticationServices

public class WebviewLoginRequest {
    public let state: String
    public let nonce: String
    public let scope: [String]?
    public let presentationContextProvider: ASWebAuthenticationPresentationContextProviding
    public let origin: String?
    public let provider: String?
    public let prefersEphemeralWebBrowserSession: Bool
    /// The `redirect_uri` of this login and its return channel. The resolved `redirect_uri` must be one
    /// of the client's authorized callback URLs, and is reused identically for the code exchange.
    /// Default: ``WebSessionMode/sdkScheme``.
    public let webSessionMode: WebSessionMode

    public init(
        state: String? = nil,
        nonce: String? = nil,
        scope: [String]? = nil,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
        origin: String? = nil,
        provider: String? = nil,
        prefersEphemeralWebBrowserSession: Bool = false,
        webSessionMode: WebSessionMode = .sdkScheme
    ) {
        self.state = state ?? "state"
        self.nonce = nonce ?? "nonce"
        self.scope = scope
        self.presentationContextProvider = presentationContextProvider
        self.origin = origin
        self.provider = provider
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        self.webSessionMode = webSessionMode
    }

    /// Same as ``init(state:nonce:scope:presentationContextProvider:origin:provider:prefersEphemeralWebBrowserSession:webSessionMode:)``,
    /// but derives the presentation context from a ``Presentation``, so the view controller
    /// does not need to conform to `ASWebAuthenticationPresentationContextProviding`.
    ///
    /// - Throws: `ReachFiveError.TechnicalError` if the view controller has been deallocated.
    @MainActor
    public convenience init(
        state: String? = nil,
        nonce: String? = nil,
        scope: [String]? = nil,
        presenting: Presentation,
        origin: String? = nil,
        provider: String? = nil,
        prefersEphemeralWebBrowserSession: Bool = false,
        webSessionMode: WebSessionMode = .sdkScheme
    ) throws {
        self.init(
            state: state,
            nonce: nonce,
            scope: scope,
            presentationContextProvider: try presenting.webAuthContextProvider(),
            origin: origin,
            provider: provider,
            prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession,
            webSessionMode: webSessionMode
        )
    }
}
