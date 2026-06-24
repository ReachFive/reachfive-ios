import Foundation
import AuthenticationServices

public extension ReachFive {

    func webviewLogin(_ request: WebviewLoginRequest) async throws -> AuthToken {
        try await webviewLogin(request, using: WebAuthenticationSession())
    }

    /// Orchestrates the whole web login: PKCE, authorize URL, web authentication session, then code
    /// exchange. The `webAuthentication` session is injected so a provider whose flow ends on a
    /// universal link can complete it out-of-band from `application(_:continue:)` (see `DefaultProvider`).
    internal func webviewLogin(_ request: WebviewLoginRequest, using webAuthentication: WebAuthenticationSession) async throws -> AuthToken {

        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)

        let scope = (request.scope ?? scope)
        let redirectUri = request.redirectUri ?? sdkConfig.redirectUri
        let authURL = buildAuthorizeURL(pkce: pkce, state: request.state, nonce: request.nonce, scope: scope, origin: request.origin, provider: request.provider, redirectUri: redirectUri)

        let callbackURL = try await webAuthentication.start(
            url: authURL,
            callbackURLScheme: reachFiveApi.sdkConfig.baseScheme,
            presentationContextProvider: request.presentationContextProvider,
            prefersEphemeralWebBrowserSession: request.prefersEphemeralWebBrowserSession)

        let params = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true)?.queryItems
        guard let params, let code = params.first(where: { $0.name == "code" })?.value else {
            throw ReachFiveError.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params))
        }

        return try await self.authWithCode(code: code, pkce: pkce, redirectUri: redirectUri)
    }
}
