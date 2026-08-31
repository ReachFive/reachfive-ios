import Foundation

public enum LoginFlow {
    case AchievedLogin(authToken: AuthToken)
    case OngoingStepUp(token: String, availableMfaCredentialItemTypes: [MfaCredentialItemType])
}

public enum SignupFlow {
    case AchievedLogin(authToken: AuthToken)
    case AwaitingIdentifierVerification
}

extension ReachFive {
    /// - Parameter captcha: a token, if the client requires a captcha on `signup_token`, the endpoint
    ///   this method calls. See ``Captcha``.
    public func signup(profile: ProfileSignupRequest, redirectUrl: URL? = nil, scope: [String]? = nil, origin: String? = nil, captcha: Captcha? = nil) async throws -> SignupFlow {
        let signupRequest = SignupRequest(
            clientId: sdkConfig.clientId,
            data: profile,
            scope: (scope ?? self.scope).joined(separator: " "),
            redirectUrl: redirectUrl,
            origin: origin,
            captcha: captcha
        )
        let token = try await reachFiveApi.signupWithPassword(signupRequest: signupRequest)
        guard let accessToken = token.accessToken else {
            return .AwaitingIdentifierVerification
        }
        return try .AchievedLogin(authToken: AuthToken.fromOpenIdTokenResponse(AccessTokenResponse(idToken: token.idToken, accessToken: accessToken, refreshToken: token.refreshToken, code: nil, tokenType: token.tokenType, expiresIn: token.expiresIn, error: nil, errorDescription: nil)))
    }

    /// - Parameter captcha: a token, if the client requires a captcha on `password_login`. See ``Captcha``.
    public func loginWithPassword(
        email: String? = nil,
        phoneNumber: String? = nil,
        customIdentifier: String? = nil,
        password: String,
        scope: [String]? = nil,
        origin: String? = nil,
        captcha: Captcha? = nil
    ) async throws -> LoginFlow {
        let strScope = (scope ?? self.scope).joined(separator: " ")
        let loginRequest = LoginRequest(
            email: email,
            phoneNumber: phoneNumber,
            customIdentifier: customIdentifier,
            password: password,
            grantType: "password",
            clientId: sdkConfig.clientId,
            scope: strScope,
            origin: origin,
            captcha: captcha
        )
        let resp = try await reachFiveApi.loginWithPassword(loginRequest: loginRequest)

        guard resp.mfaRequired == true else {
            let token = try await loginCallback(tkn: resp.tkn, scopes: scope, origin: origin)
            return .AchievedLogin(authToken: token)
        }

        // The step-up PKCE must outlive this call: the app comes back through the MFA redirect URI.
        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)
        let stepUpResponse = try await reachFiveApi.startMfaStepUp(StartMfaStepUpRequest(clientId: sdkConfig.clientId, redirectUri: sdkConfig.redirectUri, pkce: pkce, scope: strScope, tkn: resp.tkn))
        return LoginFlow.OngoingStepUp(token: stepUpResponse.token, availableMfaCredentialItemTypes: stepUpResponse.amr)
    }
}
