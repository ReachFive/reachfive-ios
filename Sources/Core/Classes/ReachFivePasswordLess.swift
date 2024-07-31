import Foundation
import BrightFutures

public enum PasswordLessRequest {
    case Email(email: String, redirectUri: String?, origin: String? = nil)
    case PhoneNumber(phoneNumber: String, redirectUri: String?, origin: String? = nil)
}

public extension ReachFive {
    
    func addPasswordlessCallback(passwordlessCallback: @escaping PasswordlessCallback) {
        self.passwordlessCallback = passwordlessCallback
    }
    
    func startPasswordless(_ request: PasswordLessRequest) -> Future<(), ReachFiveError> {
        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)
        switch request {
        case let .Email(email, redirectUri, origin):
            let startPasswordlessRequest = StartPasswordlessRequest(
                clientId: sdkConfig.clientId,
                email: email,
                authType: .MagicLink,
                redirectUri: redirectUri ?? sdkConfig.scheme,
                codeChallenge: pkce.codeChallenge,
                codeChallengeMethod: pkce.codeChallengeMethod,
                origin: origin
            )
            return reachFiveApi.startPasswordless(startPasswordlessRequest)
        case let .PhoneNumber(phoneNumber, redirectUri, origin):
            let startPasswordlessRequest = StartPasswordlessRequest(
                clientId: sdkConfig.clientId,
                phoneNumber: phoneNumber,
                authType: .SMS,
                redirectUri: redirectUri ?? sdkConfig.scheme,
                codeChallenge: pkce.codeChallenge,
                codeChallengeMethod: pkce.codeChallengeMethod,
                origin: origin
            )
            return reachFiveApi.startPasswordless(startPasswordlessRequest)
        }
    }
    
    func verifyPasswordlessCode(verifyAuthCodeRequest: VerifyAuthCodeRequest) -> Future<AuthToken, ReachFiveError> {
        let pkce: Pkce? = storage.take(key: pkceKey)
        guard let pkce else {
            return Future(error: .TechnicalError(reason: "Pkce not found"))
        }
        return reachFiveApi
            .verifyAuthCode(verifyAuthCodeRequest: verifyAuthCodeRequest)
            .flatMap { _ in
                let verifyPasswordlessRequest = VerifyPasswordlessRequest(
                    email: verifyAuthCodeRequest.email,
                    phoneNumber: verifyAuthCodeRequest.phoneNumber,
                    verificationCode: verifyAuthCodeRequest.verificationCode,
                    state: "passwordless",
                    clientId: self.sdkConfig.clientId,
                    responseType: "code",
                    origin: verifyAuthCodeRequest.origin
                )
                return self.reachFiveApi
                    .verifyPasswordless(verifyPasswordlessRequest: verifyPasswordlessRequest)
                    .flatMap { response in
                        
                        guard let code = response.code else {
                            return Future(error: .TechnicalError(reason: "No authorization code"))
                        }
                        
                        return self.authWithCode(code: code, pkce: pkce)
                    }
            }
    }
    
    internal func interceptPasswordless(_ url: URL) {
        let params = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems
        
        let pkce: Pkce? = storage.take(key: pkceKey)
        guard let pkce else {
            passwordlessCallback?(.failure(.TechnicalError(reason: "Pkce not found")))
            return
        }
        guard let params, let code = params.first(where: { $0.name == "code" })?.value else {
            passwordlessCallback?(.failure(.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params))))
            return
        }
        
        authWithCode(code: code, pkce: pkce)
            .onComplete { result in
                self.passwordlessCallback?(result)
            }
    }
}
