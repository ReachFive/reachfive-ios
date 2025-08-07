import Foundation
import AuthenticationServices

public extension ReachFive {

    func webviewLogin(_ request: WebviewLoginRequest) async throws -> AuthToken {

        let pkce = Pkce.generate()
        let scope = (request.scope ?? scope)
        let authURL = buildAuthorizeURL(pkce: pkce, state: request.state, nonce: request.nonce, scope: scope, origin: request.origin, provider: request.provider)

        let callbackURL = try await webAuthenticationSession(
            url: authURL,
            callbackURLScheme: reachFiveApi.sdkConfig.baseScheme,
            presentationContextProvider: request.presentationContextProvider,
            prefersEphemeralWebBrowserSession: request.prefersEphemeralWebBrowserSession)
        
        let params = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true)?.queryItems
        guard let params, let code = params.first(where: { $0.name == "code" })?.value else {
            throw ReachFiveError.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params))
        }

        return try await self.authWithCode(code: code, pkce: pkce)
    }
}
