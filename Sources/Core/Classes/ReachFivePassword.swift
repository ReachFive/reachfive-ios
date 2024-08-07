import Foundation
import BrightFutures

public extension ReachFive {
    func signup(profile: ProfileSignupRequest, redirectUrl: String? = nil, scope: [String]? = nil, origin: String? = nil) -> Future<AuthToken, ReachFiveError> {
        let signupRequest = SignupRequest(
            clientId: sdkConfig.clientId,
            data: profile,
            scope: (scope ?? self.scope).joined(separator: " "),
            redirectUrl: redirectUrl,
            origin: origin
        )
        return reachFiveApi
            .signupWithPassword(signupRequest: signupRequest)
            .flatMap({ AuthToken.fromOpenIdTokenResponseFuture($0) })
    }
    
    func loginWithPassword(
        email: String? = nil,
        phoneNumber: String? = nil,
        customIdentifier: String? = nil,
        password: String,
        scope: [String]? = nil,
        origin: String? = nil
    ) -> Future<AuthToken, ReachFiveError> {
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
            .flatMap({ resp in
                if(resp.mfaRequired == true) {
                    let pkce = Pkce.generate()
                    self.storage.save(key: self.pkceKey, value: pkce)
                    return self.reachFiveApi.startMfaStepUp(StartMfaStepUpRequest(clientId: self.sdkConfig.clientId, redirectUri: self.sdkConfig.redirectUri, codeChallenge: pkce.codeChallenge, codeChallengeMethod: pkce.codeChallengeMethod, scope: strScope, tkn: resp.tkn, stepUp: nil), authToken: nil)
                        .map({ res in
                            AuthToken(
                                idToken: nil,
                                accessToken: nil,
                                refreshToken: nil,
                                tokenType: nil,
                                expiresIn: nil,
                                token: res.token,
                                amr: res.amr,
                                user: nil
                            )
                        })
                } else {
                    return self.loginCallback(tkn: resp.tkn, scopes: scope, origin: origin)
                }
            })
    }
}
