
import Foundation

public enum LoginFlow {
    case AchievedLogin(authToken: AuthToken)
    case OngoingStepUp(token: String, availableMfaCredentialItemTypes: [MfaCredentialItemType])
}

public extension ReachFive {
    func signup(profile: ProfileSignupRequest, redirectUrl: String? = nil, scope: [String]? = nil, origin: String? = nil) async throws -> AuthToken {
        let signupRequest = SignupRequest(
            clientId: sdkConfig.clientId,
            data: profile,
            scope: (scope ?? self.scope).joined(separator: " "),
            redirectUrl: redirectUrl,
            origin: origin
        )
        let token = try await reachFiveApi.signupWithPassword(signupRequest: signupRequest)
        return try AuthToken.fromOpenIdTokenResponse(token)
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

        if resp.mfaRequired != true {
            let token = try await self.loginCallback(tkn: resp.tkn, scopes: scope, origin: origin)
            return .AchievedLogin(authToken: token)
        }

        let pkce = Pkce.generate()
        self.storage.save(key: self.pkceKey, value: pkce)
        let stepUpResponse = try await self.reachFiveApi.startMfaStepUp(StartMfaStepUpRequest(clientId: self.sdkConfig.clientId, redirectUri: self.sdkConfig.redirectUri, pkce: pkce, scope: strScope, tkn: resp.tkn))
        return LoginFlow.OngoingStepUp(token: stepUpResponse.token, availableMfaCredentialItemTypes: stepUpResponse.amr)
    }
}
