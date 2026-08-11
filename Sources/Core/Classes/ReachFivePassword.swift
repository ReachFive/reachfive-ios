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
    public func signup(profile: ProfileSignupRequest, redirectUrl: URL? = nil, scope: [String]? = nil, origin: String? = nil) async throws -> SignupFlow {
        let signupRequest = SignupRequest(
            clientId: sdkConfig.clientId,
            data: profile,
            scope: (scope ?? self.scope).joined(separator: " "),
            redirectUrl: redirectUrl,
            origin: origin
        )
        let token = try await reachFiveApi.signupWithPassword(signupRequest: signupRequest)
        guard let accessToken = token.accessToken else {
            return .AwaitingIdentifierVerification
        }
        return try .AchievedLogin(authToken: AuthToken.fromOpenIdTokenResponse(AccessTokenResponse(idToken: token.idToken, accessToken: accessToken, refreshToken: token.refreshToken, code: nil, tokenType: token.tokenType, expiresIn: token.expiresIn, error: nil, errorDescription: nil)))
    }

    public func loginWithPassword(
        email: String? = nil,
        phoneNumber: String? = nil,
        customIdentifier: String? = nil,
        password: String,
        scope: [String]? = nil,
        origin: String? = nil,
        upgradingToPasskey passkeyRequest: NewPasskeyRequest? = nil
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
            origin: origin
        )
        let resp = try await reachFiveApi.loginWithPassword(loginRequest: loginRequest)

        guard resp.mfaRequired == true else {
            let token = try await loginCallback(tkn: resp.tkn, scopes: scope, origin: origin)
            await upgradeToPasskeyIfRequested(passkeyRequest, authToken: token)
            return .AchievedLogin(authToken: token)
        }

        // The step-up PKCE must outlive this call: the app comes back through the MFA redirect URI.
        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)
        let stepUpResponse = try await reachFiveApi.startMfaStepUp(StartMfaStepUpRequest(clientId: sdkConfig.clientId, redirectUri: sdkConfig.redirectUri, pkce: pkce, scope: strScope, tkn: resp.tkn))
        return LoginFlow.OngoingStepUp(token: stepUpResponse.token, availableMfaCredentialItemTypes: stepUpResponse.amr)
    }

    /// Runs the automatic passkey upgrade a password sign-in asked for, if the OS supports it.
    ///
    /// Swallows every error on purpose: the sign-in has already succeeded, and an upgrade — invisible by
    /// nature — must never be what turns it into a failure. Callers that want to know the outcome, or to
    /// keep the two round trips off the sign-in path, call ``upgradeToPasskey(withRequest:authToken:)``
    /// themselves instead of passing `upgradingToPasskey`.
    private func upgradeToPasskeyIfRequested(_ passkeyRequest: NewPasskeyRequest?, authToken: AuthToken) async {
        guard #available(iOS 18.0, *), let passkeyRequest else { return }

        do {
            let upgraded = try await upgradeToPasskey(withRequest: passkeyRequest, authToken: authToken)
            Logger.shared.log("Automatic passkey upgrade: \(upgraded ? "passkey created" : "declined by the system, or the account already has one")")
        } catch {
            Logger.shared.log("Automatic passkey upgrade failed: \(error)")
        }
    }
}
