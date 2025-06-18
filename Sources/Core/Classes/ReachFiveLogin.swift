import Foundation


public extension ReachFive {

    func logout() -> Result<(), ReachFiveError> {
        providers
            .map { $0.logout() }
            .sequence()
            .flatMap { _ in self.reachFiveApi.logout() }
    }

    func refreshAccessToken(authToken: AuthToken) -> Result<AuthToken, ReachFiveError> {
        let refreshRequest = RefreshRequest(
            clientId: sdkConfig.clientId,
            refreshToken: authToken.refreshToken ?? "",
            redirectUri: sdkConfig.scheme
        )
        return reachFiveApi
            .refreshAccessToken(refreshRequest)
            .flatMap({ AuthToken.fromOpenIdTokenResponseFuture($0) })
    }

    func loginCallback(tkn: String, scopes: [String]?, origin: String? = nil) -> Result<AuthToken, ReachFiveError> {
        let pkce = Pkce.generate()
        let scope = (scopes ?? scope).joined(separator: " ")

        return reachFiveApi.loginCallback(loginCallback: LoginCallback(sdkConfig: sdkConfig, scope: scope, pkce: pkce, tkn: tkn, origin: origin))
            .flatMap({ self.authWithCode(code: $0, pkce: pkce) })
    }

    func loginCallbackAsync(tkn: String, scopes: [String]?, origin: String? = nil) async throws -> AuthToken {
        let pkce = Pkce.generate()
        let scope = (scopes ?? scope).joined(separator: " ")

        let code = try await reachFiveApi.loginCallbackAsync(loginCallback: LoginCallback(sdkConfig: sdkConfig, scope: scope, pkce: pkce, tkn: tkn, origin: origin))
        return try await self.authWithCodeAsync(code: code, pkce: pkce)
    }

    func buildAuthorizeURL(pkce: Pkce, state: String? = nil, nonce: String? = nil, scope: [String]? = nil, origin: String? = nil, provider: String? = nil) -> URL {
        let scope = (scope ?? self.scope).joined(separator: " ")
        let options = [
            "provider": provider,
            "client_id": sdkConfig.clientId,
            "redirect_uri": sdkConfig.redirectUri,
            "response_type": "code",
            "scope": scope,
            "code_challenge": pkce.codeChallenge,
            "code_challenge_method": pkce.codeChallengeMethod,
            "state": state,
            "nonce": nonce,
            "origin": origin,
        ]

        return reachFiveApi.buildAuthorizeURL(queryParams: options)
    }

    func authWithCode(code: String, pkce: Pkce) -> Result<AuthToken, ReachFiveError> {
        let authCodeRequest = AuthCodeRequest(
            clientId: sdkConfig.clientId,
            code: code,
            redirectUri: sdkConfig.scheme,
            pkce: pkce)
        return reachFiveApi
            .authWithCode(authCodeRequest: authCodeRequest)
            .flatMap({ AuthToken.fromOpenIdTokenResponseFuture($0) })
    }

    func authWithCodeAsync(code: String, pkce: Pkce) async throws -> AuthToken {
        let authCodeRequest = AuthCodeRequest(
            clientId: sdkConfig.clientId,
            code: code,
            redirectUri: sdkConfig.scheme,
            pkce: pkce)

        let openIdTokenResponse = try await reachFiveApi
            .authWithCodeAsync(authCodeRequest: authCodeRequest)

        return try AuthToken.fromOpenIdTokenResponse(openIdTokenResponse: openIdTokenResponse).get()
    }
}
