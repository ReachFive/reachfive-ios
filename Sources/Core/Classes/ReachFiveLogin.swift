import Foundation


public extension ReachFive {

    func logout() async throws -> Void {
        //TODO: déconnecter les providers en parallèle ?
        await providers
            .traverse { await $0.logout() }
            .flatMapAsync { _ in await self.reachFiveApi.logout() }
    }

    func refreshAccessToken(authToken: AuthToken) async throws -> AuthToken {
        let refreshRequest = RefreshRequest(
            clientId: sdkConfig.clientId,
            refreshToken: authToken.refreshToken ?? "",
            redirectUri: sdkConfig.scheme
        )
        return await reachFiveApi
            .refreshAccessToken(refreshRequest)
            .flatMap({ AuthToken.fromOpenIdTokenResponse($0) })
    }

    func loginCallback(tkn: String, scopes: [String]?, origin: String? = nil) async throws -> AuthToken {
        let pkce = Pkce.generate()
        let scope = (scopes ?? scope).joined(separator: " ")

        return await reachFiveApi.loginCallback(loginCallback: LoginCallback(sdkConfig: sdkConfig, scope: scope, pkce: pkce, tkn: tkn, origin: origin))
            .flatMapAsync({ await self.authWithCode(code: $0, pkce: pkce) })
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
        return await reachFiveApi
            .authWithCode(authCodeRequest: authCodeRequest)
            .flatMap({ AuthToken.fromOpenIdTokenResponse($0) })
    }
}
