import BrightFutures
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
        let token = try await reachFiveApi
            .signupWithPassword(signupRequest: signupRequest)
        return try AuthToken.fromOpenIdTokenResponse(openIdTokenResponse: token).get()
    }

    func loginWithPassword(
        email: String? = nil,
        phoneNumber: String? = nil,
        customIdentifier: String? = nil,
        password: String,
        scope: [String]? = nil,
        origin: String? = nil
    ) -> Future<LoginFlow, ReachFiveError> {
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
        return reachFiveApi
            .loginWithPassword(loginRequest: loginRequest)
            .flatMap { resp in
                if resp.mfaRequired == true {
                    let pkce = Pkce.generate()
                    self.storage.save(key: self.pkceKey, value: pkce)
                    return self.reachFiveApi.startMfaStepUp(StartMfaStepUpRequest(clientId: self.sdkConfig.clientId, redirectUri: self.sdkConfig.redirectUri, pkce: pkce, scope: strScope, tkn: resp.tkn))
                        .map { intiationStepUpResponse in
                            LoginFlow.OngoingStepUp(token: intiationStepUpResponse.token, availableMfaCredentialItemTypes: intiationStepUpResponse.amr)
                        }
                } else {
                    return self.loginCallback(tkn: resp.tkn, scopes: scope, origin: origin)
                        .map { res in
                            .AchievedLogin(authToken: res)
                        }
                }
            }
    }

    //TODO Avec le Reach5 version X qui sera pur async/await, livrer un Reach5FutureBridge (un fork de reachfive-ios) qui ajoutera aussi les méthodes actuelles avec les Future et qui utilisera de manière sous-jacente les version async/await
    // On ne garde pas de différentes branches dans Reach5, mais le legacy sera géré dans Reach5FutureBridge.
    // Pas de nouvelle version de la sandbox, migrer la sandbox actuelle pour utiliser les fonctions async/await. La version Future sera dans Reach5FutureBridge.
    func loginWithPasswordAsync(
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
        print("async loginWithPassword")
        let resp = try await reachFiveApi.loginWithPasswordAsync(loginRequest: loginRequest)
        if resp.mfaRequired == true {
            throw ReachFiveError.AuthFailure(reason: "MfaRequired", apiError: nil)
        } else {
            let res = try await self.loginCallbackAsync(tkn: resp.tkn, scopes: scope, origin: origin)
            return .AchievedLogin(authToken: res)
        }
    }
}
