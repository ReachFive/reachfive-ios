import Foundation

public extension ReachFive {

    func logout(webSessionLogout request: WebSessionLogoutRequest? = nil, revoke token: AuthToken? = nil) async throws {
        // Don't stop for errors along the way

        for provider in providers {
            try? await provider.logout()
        }

        if let request {
            let options = [
                "post_logout_redirect_uri": sdkConfig.redirectUri,
                "origin": request.origin,
            ]

            // Passe par le porteur pour que la session ait un propriétaire unique. Le logout se complète
            // in-band via le scheme custom (post_logout_redirect_uri) ; pas de complétion hors-bande.
            let _ = try? await webAuthSessionHolder.run(
                url: reachFiveApi.buildLogoutURL(queryParams: options),
                expectedCallback: URL(string: sdkConfig.redirectUri),
                callbackURLScheme: sdkConfig.baseScheme,
                presentationContextProvider: request.presentationContextProvider,
                prefersEphemeralWebBrowserSession: false)
        }

        if let token {
            try? await revokeToken(authToken: token)
        }

        try await self.reachFiveApi.logout()
    }

    func loginCallback(tkn: String, scopes: [String]?, origin: String? = nil) async throws -> AuthToken {
        let pkce = Pkce.generate()
        let scope = (scopes ?? scope).joined(separator: " ")

        let code = try await reachFiveApi.loginCallback(loginCallback: LoginCallback(sdkConfig: sdkConfig, scope: scope, pkce: pkce, tkn: tkn, origin: origin))
        return try await self.authWithCode(code: code, pkce: pkce)
    }

    func buildAuthorizeURL(pkce: Pkce, state: String? = nil, nonce: String? = nil, scope: [String]? = nil, origin: String? = nil, provider: String? = nil, redirectUri: String? = nil) -> URL {
        let scope = (scope ?? self.scope).joined(separator: " ")
        let options = [
            "provider": provider,
            "client_id": sdkConfig.clientId,
            "redirect_uri": redirectUri ?? sdkConfig.redirectUri,
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

    func authWithCode(code: String, pkce: Pkce, redirectUri: String? = nil) async throws -> AuthToken {
        let authCodeRequest = AuthCodeRequest(
            clientId: sdkConfig.clientId,
            code: code,
            redirectUri: redirectUri ?? sdkConfig.scheme,
            pkce: pkce)
        let token = try await reachFiveApi.authWithCode(authCodeRequest: authCodeRequest)
        return try AuthToken.fromOpenIdTokenResponse(token)
    }
}
