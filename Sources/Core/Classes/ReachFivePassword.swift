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
        let loginRequest = LoginRequest(
            email: email,
            phoneNumber: phoneNumber,
            customIdentifier: customIdentifier,
            password: password,
            grantType: "password",
            clientId: sdkConfig.clientId,
            scope: (scope ?? self.scope).joined(separator: " "),
            origin: origin
        )
        return reachFiveApi
            .loginWithPassword(loginRequest: loginRequest)
            .flatMap({ self.loginCallback(tkn: $0.tkn, scopes: scope, origin: origin) })
    }
}
