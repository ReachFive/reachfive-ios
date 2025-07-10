import Foundation

public extension ReachFive {

    func logout() async throws -> Void {
        for provider in providers {
            do {
                try await provider.logout()
            } catch {
                // Continue logging out other providers
            }
        }
        try await self.reachFiveApi.logout()
    }

    func refreshAccessToken(authToken: AuthToken) async throws -> AuthToken {
        let refreshRequest = RefreshRequest(
            clientId: sdkConfig.clientId,
            refreshToken: authToken.refreshToken,
            redirectUri: sdkConfig.scheme
        )
        let token = try await reachFiveApi.refreshAccessToken(refreshRequest)
        return try AuthToken.fromOpenIdTokenResponse(token)
    }

    func loginCallback(tkn: String, scopes: [String]?, origin: String? = nil) async throws -> AuthToken {
        let pkce = Pkce.generate()
        let scope = (scopes ?? scope).joined(separator: " ")

        let code = try await reachFiveApi.loginCallback(loginCallback: LoginCallback(sdkConfig: sdkConfig, scope: scope, pkce: pkce, tkn: tkn, origin: origin))
        return try await self.authWithCode(code: code, pkce: pkce)
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

    func authWithCode(code: String, pkce: Pkce) async throws -> AuthToken {
        let authCodeRequest = AuthCodeRequest(
            clientId: sdkConfig.clientId,
            code: code,
            redirectUri: sdkConfig.scheme,
            pkce: pkce)
        let token = try await reachFiveApi.authWithCode(authCodeRequest: authCodeRequest)
        return try AuthToken.fromOpenIdTokenResponse(token)
    }
}
