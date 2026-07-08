import Foundation

public enum LoginFlow {
    case AchievedLogin(authToken: AuthToken)
    case OngoingStepUp(token: String, availableMfaCredentialItemTypes: [MfaCredentialItemType])
}

public enum SignupFlow {
    case AchievedLogin(authToken: AuthToken)
    case AwaitingIdentifierVerification
}

public extension ReachFive {
    func signup(profile: ProfileSignupRequest, redirectUrl: URL? = nil, scope: [String]? = nil, origin: String? = nil) async throws -> SignupFlow {
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

    func loginWithPassword(
        email: String? = nil,
        phoneNumber: String? = nil,
        customIdentifier: String? = nil,
        password: String,
        scope: [String]? = nil,
        origin: String? = nil
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
        return try await loginFlow(afterPasswordGrant: resp, scopes: scope, origin: origin)
    }

    /// Poursuit un login par mot de passe une fois la réponse du serveur reçue :
    /// démarre un step-up MFA si le serveur l'exige, sinon termine le login.
    /// Partagé entre ``loginWithPassword(email:phoneNumber:customIdentifier:password:scope:origin:)``
    /// et le login par mot de passe du trousseau (`CredentialManager`).
    /// Non testable unitairement tant que ReachFiveApi n'est pas abstrait derrière un protocole (appels réseau directs).
    internal func loginFlow(afterPasswordGrant resp: TknMfa, scopes: [String]?, origin: String?) async throws -> LoginFlow {
        guard resp.mfaRequired == true else {
            let token = try await loginCallback(tkn: resp.tkn, scopes: scopes, origin: origin)
            return .AchievedLogin(authToken: token)
        }

        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)
        let stepUpResponse = try await reachFiveApi.startMfaStepUp(StartMfaStepUpRequest(clientId: sdkConfig.clientId, redirectUri: sdkConfig.redirectUri, pkce: pkce, scope: (scopes ?? scope).joined(separator: " "), tkn: resp.tkn))
        return LoginFlow.OngoingStepUp(token: stepUpResponse.token, availableMfaCredentialItemTypes: stepUpResponse.amr)
    }
}
