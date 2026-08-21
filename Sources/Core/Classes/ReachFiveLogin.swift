import Foundation

extension ReachFive {
    public func logout(webSessionLogout request: WebSessionLogoutRequest? = nil, revoke token: AuthToken? = nil) async throws {
        // Don't stop for errors along the way

        for provider in providers {
            try? await provider.logout()
        }

        if let request {
            let options = [
                "post_logout_redirect_uri": sdkConfig.redirectUri.absoluteString,
                "origin": request.origin,
            ]

            _ = try? await webAuthSession.start(
                url: reachFiveApi.buildLogoutURL(queryParams: options),
                mode: .customScheme,
                // A logout callback carries no `code` and is intercepted by the sheet, so the out-of-band
                // channel must not be prepared: a login code straying in would otherwise resolve this logout
                // and be swallowed (the logout's continuation ignores the URL).
                expectsAuthorizationCode: false,
                presentationContextProvider: request.presentationContextProvider,
                prefersEphemeralWebBrowserSession: false
            )
        }

        if let token {
            try? await revokeToken(authToken: token)
        }

        try await reachFiveApi.logout()
    }

    /// Exchanges a ReachFive `tkn` for an ``AuthToken``, the last step of the passkey, passwordless and
    /// password flows.
    public func loginCallback(tkn: String, scopes: [String]?, origin: String? = nil) async throws -> AuthToken {
        let pkce = Pkce.generate()
        let code = try await reachFiveApi.authorize(params: authorizeParams(pkce: pkce, scope: scopes, origin: origin, adding: ["tkn": tkn]))
        return try await authWithCode(code: code, pkce: pkce)
    }

    /// Exchanges an ID token obtained from a native provider SDK for a ReachFive ``AuthToken``.
    ///
    /// The provider counterpart of ``loginCallback(tkn:scopes:origin:)``, for a caller that has already run
    /// the provider's own sign-in: used by Sign In With Apple and by the Facebook provider's limited login,
    /// and meant for integrators writing their own ``Provider``. `provider` is the name declared in the
    /// ReachFive console — pass ``ProviderConfig/providerWithVariant`` to target a specific native variant.
    ///
    /// Sign In With Apple only hands out the full name on the user's very first authorization: forward
    /// `givenName` and `familyName` then, or they are lost for good.
    ///
    /// - Parameters:
    ///   - nonce: the ``Pkce`` whose ``Pkce/codeChallenge`` was handed to the provider as its nonce. Pass
    ///     that very same instance: its code verifier is what ReachFive checks against the nonce claim of
    ///     `idToken`.
    public func login(
        withProvider provider: String,
        idToken: String,
        nonce: Pkce,
        scope: [String]? = nil,
        origin: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil
    ) async throws -> AuthToken {
        let pkce = Pkce.generate()
        let code = try await reachFiveApi.authorize(params: authorizeParams(pkce: pkce, scope: scope, origin: origin, adding: [
            "provider": provider,
            "id_token": idToken,
            "nonce": nonce.codeVerifier,
            "given_name": givenName,
            "family_name": familyName,
        ]))
        return try await authWithCode(code: code, pkce: pkce)
    }

    public func buildAuthorizeURL(pkce: Pkce, state: String? = nil, nonce: String? = nil, scope: [String]? = nil, origin: String? = nil, provider: String? = nil, redirectUri: URL? = nil, loginUrlFragment: [String: String]? = nil) -> URL {
        let url = reachFiveApi.buildAuthorizeURL(queryParams: authorizeParams(pkce: pkce, scope: scope, origin: origin, redirectUri: redirectUri, adding: [
            "provider": provider,
            "state": state,
            "nonce": nonce,
        ]))

        // `loginUrlFragment` is intentionally carried in the URL fragment, not a query param. In a
        // token-orchestration setup, /oauth/authorize 302-redirects to the client's Login URL. A query
        // param added here is dropped at that redirect (the backend doesn't forward it), whereas the
        // fragment is never sent to the server but is re-applied by the browser onto the redirect target
        // (whose Location carries no fragment). The Login URL thus receives it as `#key=value&...` and can
        // read it via window.location.hash to theme the page per calling channel.
        guard let loginUrlFragment, !loginUrlFragment.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else
        {
            return url
        }
        // Reuse URLComponents' query-encoding (rather than hand-rolling "key=value" pairs) so keys/values
        // containing `&`, `=`, spaces, etc. are correctly percent-encoded within the fragment.
        var fragmentComponents = URLComponents()
        fragmentComponents.queryItems = loginUrlFragment.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.percentEncodedFragment = fragmentComponents.percentEncodedQuery
        return components.url ?? url
    }

    /// The parameters every `/oauth/authorize` call sends, plus what `extra` adds — shared keys winning over
    /// colliding ones, so no caller can redefine the grant it asks for. `redirectUri` overrides a shared key
    /// rather than adding one: the same URL must then reach ``authWithCode(code:pkce:redirectUri:)``.
    func authorizeParams(pkce: Pkce, scope: [String]?, origin: String?, redirectUri: URL? = nil, adding extra: [String: String?]) -> [String: String?] {
        let shared: [String: String?] = [
            "client_id": sdkConfig.clientId,
            "response_type": "code",
            "redirect_uri": (redirectUri ?? sdkConfig.redirectUri).absoluteString,
            "scope": (scope ?? self.scope).joined(separator: " "),
            "code_challenge": pkce.codeChallenge,
            "code_challenge_method": pkce.codeChallengeMethod,
            "origin": origin,
        ]
        return shared.merging(extra) { shared, _ in shared }
    }

    public func authWithCode(code: String, pkce: Pkce, redirectUri: URL? = nil) async throws -> AuthToken {
        let authCodeRequest = AuthCodeRequest(
            clientId: sdkConfig.clientId,
            code: code,
            redirectUri: redirectUri ?? sdkConfig.redirectUri,
            pkce: pkce
        )
        let token = try await reachFiveApi.authWithCode(authCodeRequest: authCodeRequest)
        return try AuthToken.fromOpenIdTokenResponse(token)
    }
}
