import Foundation

public enum PasswordLessRequest {
    case Email(email: String, redirectUri: URL?, origin: String? = nil)
    case PhoneNumber(phoneNumber: String, redirectUri: URL?, origin: String? = nil)
}

/// The `redirect_uri` a passwordless code is bound to, saved with the challenge of the PKCE started alongside.
private struct PasswordlessRedirect: Codable {
    let codeChallenge: String
    let redirectUri: URL
}

extension ReachFive {
    public func addPasswordlessCallback(passwordlessCallback: @escaping PasswordlessCallback) {
        self.passwordlessCallback = passwordlessCallback
    }

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
        storage.save(key: passwordlessRedirectUriKey, value: PasswordlessRedirect(codeChallenge: pkce.codeChallenge, redirectUri: startPasswordlessRequest.redirectUri))
        return try await reachFiveApi.startPasswordless(startPasswordlessRequest)
    }

    public func verifyPasswordlessCode(verifyAuthCodeRequest: VerifyAuthCodeRequest) async throws -> AuthToken {
        let pkce: Pkce? = storage.take(key: pkceKey)
        let redirectUri = takePasswordlessRedirectUri(for: pkce)
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

        return try await authWithCode(code: code, pkce: pkce, redirectUri: redirectUri)
    }

    /// The `redirect_uri` `startPasswordless` bound its code to, only if `pkce` is the one it started with.
    /// The PKCE key is shared with other flows (web login, MFA step-up) whose callback can also reach
    /// `interceptPasswordless`: a value left by an abandoned passwordless must not apply to their code, which
    /// was obtained with `SdkConfig.redirectUri`.
    private func takePasswordlessRedirectUri(for pkce: Pkce?) -> URL? {
        let saved: PasswordlessRedirect? = storage.take(key: passwordlessRedirectUriKey)
        return saved.flatMap { $0.codeChallenge == pkce?.codeChallenge ? $0.redirectUri : nil }
    }

    func interceptPasswordless(_ url: URL) {
        let params = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems

        let pkce: Pkce? = storage.take(key: pkceKey)
        let redirectUri = takePasswordlessRedirectUri(for: pkce)
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
                try await self.passwordlessCallback?(.success(authWithCode(code: code, pkce: pkce, redirectUri: redirectUri)))
            } catch {
                self.passwordlessCallback?(.failure(error as! ReachFiveError))
            }
        }
    }
}
