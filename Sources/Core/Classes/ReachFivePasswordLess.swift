import Foundation


public enum PasswordLessRequest {
    case Email(email: String, redirectUri: String?, origin: String? = nil)
    case PhoneNumber(phoneNumber: String, redirectUri: String?, origin: String? = nil)
}

public extension ReachFive {

    func addPasswordlessCallback(passwordlessCallback: @escaping PasswordlessCallback) {
        self.passwordlessCallback = passwordlessCallback
    }

    func startPasswordless(_ request: PasswordLessRequest) async throws -> Void {
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
        return try await reachFiveApi.startPasswordless(startPasswordlessRequest)
    }

    func verifyPasswordlessCode(verifyAuthCodeRequest: VerifyAuthCodeRequest) async throws -> AuthToken {
        let pkce: Pkce? = storage.take(key: pkceKey)
        guard let pkce else {
            throw ReachFiveError.TechnicalError(reason: "Pkce not found")
        }
        //TODO: c'est quoi ces appels qui s'enchainent sans dépendre l'un de l'autre ?
        try await reachFiveApi.verifyAuthCode(verifyAuthCodeRequest: verifyAuthCodeRequest)
        let verifyPasswordlessRequest = VerifyPasswordlessRequest(
            email: verifyAuthCodeRequest.email,
            phoneNumber: verifyAuthCodeRequest.phoneNumber,
            verificationCode: verifyAuthCodeRequest.verificationCode,
            state: "passwordless",
            clientId: self.sdkConfig.clientId,
            responseType: "code",
            origin: verifyAuthCodeRequest.origin
        )
        let response = try await self.reachFiveApi.verifyPasswordless(verifyPasswordlessRequest: verifyPasswordlessRequest)
        guard let code = response.code else {
            throw ReachFiveError.TechnicalError(reason: "No authorization code")
        }
        
        return try await self.authWithCode(code: code, pkce: pkce)
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

        var result: Result<AuthToken, ReachFiveError>
        do {
            result = .success(try await authWithCode(code: code, pkce: pkce))
        } catch {
            result = .failure(error as! ReachFiveError)
        }
        self.passwordlessCallback?(result)
    }
}
