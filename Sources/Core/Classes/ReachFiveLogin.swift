import Foundation

public extension ReachFive {

    func logout(webSessionLogout request: WebSessionLogoutRequest? = nil, revoke token: AuthToken? = nil) async throws {
        // Don't stop for errors along the way

        for provider in providers {
            try? await provider.logout()
        }

        if let request {
            let options = [
                "post_logout_redirect_uri": sdkConfig.redirectUri.absoluteString,
                "origin": request.origin,
            ]

            let _ = try? await webAuthSession.start(
                url: reachFiveApi.buildLogoutURL(queryParams: options),
                mode: .sdkScheme,
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

    func buildAuthorizeURL(pkce: Pkce, state: String? = nil, nonce: String? = nil, scope: [String]? = nil, origin: String? = nil, provider: String? = nil, redirectUri: URL? = nil, loginUrlFragment: [String: String]? = nil) -> URL {
        let scope = (scope ?? self.scope).joined(separator: " ")
        let options = [
            "provider": provider,
            "client_id": sdkConfig.clientId,
            "redirect_uri": (redirectUri ?? sdkConfig.redirectUri).absoluteString,
            "response_type": "code",
            "scope": scope,
            "code_challenge": pkce.codeChallenge,
            "code_challenge_method": pkce.codeChallengeMethod,
            "state": state,
            "nonce": nonce,
            "origin": origin,
        ]

        let url = reachFiveApi.buildAuthorizeURL(queryParams: options)

        // `loginUrlFragment` is intentionally carried in the URL fragment, not a query param. In a
        // token-orchestration setup, /oauth/authorize 302-redirects to the client's Login URL. A query
        // param added here is dropped at that redirect (the backend doesn't forward it), whereas the
        // fragment is never sent to the server but is re-applied by the browser onto the redirect target
        // (whose Location carries no fragment). The Login URL thus receives it as `#key=value&...` and can
        // read it via window.location.hash to theme the page per calling channel.
        guard let loginUrlFragment, !loginUrlFragment.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        // Reuse URLComponents' query-encoding (rather than hand-rolling "key=value" pairs) so keys/values
        // containing `&`, `=`, spaces, etc. are correctly percent-encoded within the fragment.
        var fragmentComponents = URLComponents()
        fragmentComponents.queryItems = loginUrlFragment.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.percentEncodedFragment = fragmentComponents.percentEncodedQuery
        return components.url ?? url
    }

    func authWithCode(code: String, pkce: Pkce, redirectUri: URL? = nil) async throws -> AuthToken {
        let authCodeRequest = AuthCodeRequest(
            clientId: sdkConfig.clientId,
            code: code,
            redirectUri: redirectUri ?? sdkConfig.redirectUri,
            pkce: pkce)
        let token = try await reachFiveApi.authWithCode(authCodeRequest: authCodeRequest)
        return try AuthToken.fromOpenIdTokenResponse(token)
    }
}
