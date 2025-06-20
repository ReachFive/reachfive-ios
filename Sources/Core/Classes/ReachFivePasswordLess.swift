import Foundation


public enum PasswordLessRequest {
    case Email(email: String, redirectUri: String?, origin: String? = nil)
    case PhoneNumber(phoneNumber: String, redirectUri: String?, origin: String? = nil)
}

public extension ReachFive {

    func addPasswordlessCallback(passwordlessCallback: @escaping PasswordlessCallback) {
        self.passwordlessCallback = passwordlessCallback
    }

    func startPasswordless(_ request: PasswordLessRequest) async -> Result<(), ReachFiveError> {
        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)
        let startPasswordlessRequest = switch request {
        case let .Email(email, redirectUri, origin):
            StartPasswordlessRequest(
                clientId: sdkConfig.clientId,
                email: email,
                authType: .MagicLink,
                redirectUri: redirectUri ?? sdkConfig.scheme,
                codeChallenge: pkce.codeChallenge,
                codeChallengeMethod: pkce.codeChallengeMethod,
                origin: origin
            )
        case let .PhoneNumber(phoneNumber, redirectUri, origin):
            StartPasswordlessRequest(
                clientId: sdkConfig.clientId,
                phoneNumber: phoneNumber,
                authType: .SMS,
                redirectUri: redirectUri ?? sdkConfig.scheme,
                codeChallenge: pkce.codeChallenge,
                codeChallengeMethod: pkce.codeChallengeMethod,
                origin: origin
            )
        }
        return await reachFiveApi.startPasswordless(startPasswordlessRequest)
    }

    func verifyPasswordlessCode(verifyAuthCodeRequest: VerifyAuthCodeRequest) async -> Result<AuthToken, ReachFiveError> {
        let pkce: Pkce? = storage.take(key: pkceKey)
        guard let pkce else {
            return .failure(.TechnicalError(reason: "Pkce not found"))
        }
        return await reachFiveApi
            .verifyAuthCode(verifyAuthCodeRequest: verifyAuthCodeRequest)
            .flatMapAsync { _ in
                let verifyPasswordlessRequest = VerifyPasswordlessRequest(
                    email: verifyAuthCodeRequest.email,
                    phoneNumber: verifyAuthCodeRequest.phoneNumber,
                    verificationCode: verifyAuthCodeRequest.verificationCode,
                    state: "passwordless",
                    clientId: self.sdkConfig.clientId,
                    responseType: "code",
                    origin: verifyAuthCodeRequest.origin
                )
                return await self.reachFiveApi
                    .verifyPasswordless(verifyPasswordlessRequest: verifyPasswordlessRequest)
                    .flatMapAsync { response in

                        guard let code = response.code else {
                            return .failure(.TechnicalError(reason: "No authorization code"))
                        }

                        return await self.authWithCode(code: code, pkce: pkce)
                    }
            }
    }

    internal func interceptPasswordless(_ url: URL) async {
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

        self.passwordlessCallback?(await authWithCode(code: code, pkce: pkce))
    }
}
