import Foundation

public enum PasswordLessRequest {
    case Email(email: String, redirectUri: URL?, origin: String? = nil)
    case PhoneNumber(phoneNumber: String, redirectUri: URL?, origin: String? = nil)
}

extension ReachFive {
    public func addPasswordlessCallback(passwordlessCallback: @escaping PasswordlessCallback) {
        self.passwordlessCallback = passwordlessCallback
    }

    /// - Parameter captcha: a token, if the client requires a captcha on `passwordless`. A parameter
    ///   rather than a case of ``PasswordLessRequest``: it does not depend on the identifier. See ``Captcha``.
    public func startPasswordless(_ request: PasswordLessRequest, captcha: Captcha? = nil) async throws {
        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)
        let startPasswordlessRequest = switch request {
        case let .Email(email, redirectUri, origin):
            StartPasswordlessRequest(
                clientId: sdkConfig.clientId,
                email: email,
                authType: .MagicLink,
                redirectUri: redirectUri ?? sdkConfig.redirectUri,
                codeChallenge: pkce.codeChallenge,
                codeChallengeMethod: pkce.codeChallengeMethod,
                origin: origin,
                captcha: captcha
            )
        case let .PhoneNumber(phoneNumber, redirectUri, origin):
            StartPasswordlessRequest(
                clientId: sdkConfig.clientId,
                phoneNumber: phoneNumber,
                authType: .SMS,
                redirectUri: redirectUri ?? sdkConfig.redirectUri,
                codeChallenge: pkce.codeChallenge,
                codeChallengeMethod: pkce.codeChallengeMethod,
                origin: origin,
                captcha: captcha
            )
        }
        return try await reachFiveApi.startPasswordless(startPasswordlessRequest)
    }

    public func verifyPasswordlessCode(verifyAuthCodeRequest: VerifyAuthCodeRequest) async throws -> AuthToken {
        let pkce: Pkce? = storage.take(key: pkceKey)
        guard let pkce else {
            throw ReachFiveError.TechnicalError(reason: "Pkce not found")
        }

        try await reachFiveApi.verifyAuthCode(verifyAuthCodeRequest: verifyAuthCodeRequest)
        let verifyPasswordlessRequest = VerifyPasswordlessRequest(
            email: verifyAuthCodeRequest.email,
            phoneNumber: verifyAuthCodeRequest.phoneNumber,
            verificationCode: verifyAuthCodeRequest.verificationCode,
            state: "passwordless",
            clientId: sdkConfig.clientId,
            responseType: "code",
            origin: verifyAuthCodeRequest.origin
        )
        let response = try await reachFiveApi.verifyPasswordless(verifyPasswordlessRequest: verifyPasswordlessRequest)
        guard let code = response.code else {
            throw ReachFiveError.TechnicalError(reason: "No authorization code")
        }

        return try await authWithCode(code: code, pkce: pkce)
    }

    func interceptPasswordless(_ url: URL) {
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

        Task {
            do {
                try await self.passwordlessCallback?(.success(authWithCode(code: code, pkce: pkce)))
            } catch {
                self.passwordlessCallback?(.failure(error as! ReachFiveError))
            }
        }
    }
}
