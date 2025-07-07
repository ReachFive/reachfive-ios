
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
        let token = await reachFiveApi.signupWithPassword(signupRequest: signupRequest)
        return token.flatMap {
            AuthToken.fromOpenIdTokenResponse($0)
        }
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
        return await reachFiveApi
            .loginWithPassword(loginRequest: loginRequest)
            .flatMapAsync { resp in
                if resp.mfaRequired == true {
                    let pkce = Pkce.generate()
                    self.storage.save(key: self.pkceKey, value: pkce)
                    return await self.reachFiveApi.startMfaStepUp(StartMfaStepUpRequest(clientId: self.sdkConfig.clientId, redirectUri: self.sdkConfig.redirectUri, pkce: pkce, scope: strScope, tkn: resp.tkn))
                        .map { intiationStepUpResponse in
                            LoginFlow.OngoingStepUp(token: intiationStepUpResponse.token, availableMfaCredentialItemTypes: intiationStepUpResponse.amr)
                        }
                } else {
                    return await self.loginCallback(tkn: resp.tkn, scopes: scope, origin: origin)
                        .map { res in
                            .AchievedLogin(authToken: res)
                        }
                }
            }
    }
}
