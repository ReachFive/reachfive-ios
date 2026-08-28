import Foundation

public class ContinueEmailVerification {
    private let reachfive: ReachFive
    private let authToken: AuthToken

    fileprivate init(reachFive: ReachFive, authToken: AuthToken) {
        self.authToken = authToken
        reachfive = reachFive
    }

    public func verify(code: String, email: String, freshAuthToken: AuthToken? = nil) async throws {
        let userAuthToken = freshAuthToken ?? authToken
        let verifyEmailRequest = VerifyEmailRequest(email: email, verificationCode: code)
        return try await reachfive.reachFiveApi.verifyEmail(authToken: userAuthToken, verifyEmailRequest: verifyEmailRequest)
    }
}

public enum EmailVerificationResponse {
    case Success
    case VerificationNeeded(_ continueEmailVerification: ContinueEmailVerification)
}

extension ReachFive {
    public func getProfile(authToken: AuthToken) async throws -> Profile {
        try await reachFiveApi.getProfile(authToken: authToken)
    }

    public func sendEmailVerification(authToken: AuthToken, redirectUrl: URL? = nil) async throws -> EmailVerificationResponse {
        let sendEmailVerificationRequest = SendEmailVerificationRequest(redirectUrl: redirectUrl ?? sdkConfig.emailVerificationUri)

        let resp = try await reachFiveApi.sendEmailVerification(authToken: authToken, sendEmailVerificationRequest: sendEmailVerificationRequest)
        return switch resp.verificationEmailSent {
        case false: EmailVerificationResponse.Success
        case true: EmailVerificationResponse.VerificationNeeded(ContinueEmailVerification(reachFive: self, authToken: authToken))
        }
    }

    public func verifyEmail(authToken: AuthToken, code: String, email: String) async throws {
        let verifyEmailRequest = VerifyEmailRequest(email: email, verificationCode: code)

        return try await reachFiveApi.verifyEmail(authToken: authToken, verifyEmailRequest: verifyEmailRequest)
    }

    public func verifyPhoneNumber(
        authToken: AuthToken,
        phoneNumber: String,
        verificationCode: String
    ) async throws {
        let verifyPhoneNumberRequest = VerifyPhoneNumberRequest(
            phoneNumber: phoneNumber,
            verificationCode: verificationCode
        )
        return try await reachFiveApi
            .verifyPhoneNumber(authToken: authToken, verifyPhoneNumberRequest: verifyPhoneNumberRequest)
    }

    /// - Parameter captcha: the token obtained by the application when the client's configuration
    ///   requires a captcha on the `update_email` endpoint. See ``Captcha``.
    public func updateEmail(
        authToken: AuthToken,
        email: String,
        redirectUrl: URL? = nil,
        captcha: Captcha? = nil
    ) async throws -> Profile {
        let updateEmailRequest = UpdateEmailRequest(email: email, redirectUrl: redirectUrl, captcha: captcha)
        return try await reachFiveApi.updateEmail(
            authToken: authToken,
            updateEmailRequest: updateEmailRequest
        )
    }

    public func updatePhoneNumber(
        authToken: AuthToken,
        phoneNumber: String
    ) async throws -> Profile {
        let updatePhoneNumberRequest = UpdatePhoneNumberRequest(phoneNumber: phoneNumber)
        return try await reachFiveApi.updatePhoneNumber(
            authToken: authToken,
            updatePhoneNumberRequest: updatePhoneNumberRequest
        )
    }

    public func updateProfile(
        authToken: AuthToken,
        profile: Profile
    ) async throws -> Profile {
        try await reachFiveApi.updateProfile(authToken: authToken, profile: profile)
    }

    public func updateProfile(
        authToken: AuthToken,
        profileUpdate: ProfileUpdate
    ) async throws -> Profile {
        try await reachFiveApi.updateProfile(authToken: authToken, profileUpdate: profileUpdate)
    }

    public func updatePassword(_ updatePasswordParams: UpdatePasswordParams) async throws {
        let authToken = updatePasswordParams.getAuthToken()
        return try await reachFiveApi.updatePassword(
            authToken: authToken,
            updatePasswordRequest: UpdatePasswordRequest(
                updatePasswordParams: updatePasswordParams,
                sdkConfig: sdkConfig
            )
        )
    }

    /// - Parameter captcha: the token obtained by the application when the client's configuration
    ///   requires a captcha on the `forgot_password` endpoint. See ``Captcha``.
    public func requestPasswordReset(
        email: String? = nil,
        phoneNumber: String? = nil,
        redirectUrl: URL? = nil,
        origin: String? = nil,
        captcha: Captcha? = nil
    ) async throws {
        let requestPasswordResetRequest = RequestPasswordResetRequest(
            clientId: sdkConfig.clientId,
            email: email,
            phoneNumber: phoneNumber,
            redirectUrl: redirectUrl,
            origin: origin,
            captcha: captcha
        )
        return try await reachFiveApi.requestPasswordReset(
            requestPasswordResetRequest: requestPasswordResetRequest
        )
    }

    /// - Parameter captcha: the token obtained by the application when the client's configuration
    ///   requires a captcha on the `forgot_password` endpoint, which covers account recovery too.
    ///   See ``Captcha``.
    public func requestAccountRecovery(
        email: String? = nil,
        phoneNumber: String? = nil,
        redirectUrl: URL? = nil,
        origin: String? = nil,
        captcha: Captcha? = nil
    ) async throws {
        let requestAccountRecoveryRequest = RequestAccountRecoveryRequest(
            clientId: sdkConfig.clientId,
            email: email,
            phoneNumber: phoneNumber,
            redirectUrl: redirectUrl ?? sdkConfig.accountRecoveryUri,
            origin: origin,
            captcha: captcha
        )
        return try await reachFiveApi.requestAccountRecovery(requestAccountRecoveryRequest)
    }

    /// Lists all passkeys the user has registered
    public func listWebAuthnCredentials(authToken: AuthToken) async throws -> [DeviceCredential] {
        try await reachFiveApi.getWebAuthnRegistrations(authToken: authToken)
    }

    /// Deletes a passkey the user has registered
    public func deleteWebAuthnRegistration(id: String, authToken: AuthToken) async throws {
        try await reachFiveApi.deleteWebAuthnRegistration(id: id, authToken: authToken)
    }

    public func addAccountRecoveryCallback(accountRecoveryCallback: @escaping AccountRecoveryCallback) {
        self.accountRecoveryCallback = accountRecoveryCallback
    }

    public func addEmailVerificationCallback(emailVerificationCallback: @escaping EmailVerificationCallback) {
        self.emailVerificationCallback = emailVerificationCallback
    }

    public func interceptEmailVerification(_ url: URL) {
        let params = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems
        if let error = params?.first(where: { $0.name == "error" })?.value {
            emailVerificationCallback?(.failure(.TechnicalError(reason: error, apiError: ApiError(fromQueryParams: params))))
            return
        }
        emailVerificationCallback?(.success(()))
    }

    public func interceptAccountRecovery(_ url: URL) {
        let params = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems
        if let error = params?.first(where: { $0.name == "error" })?.value {
            accountRecoveryCallback?(.failure(.TechnicalError(reason: error, apiError: ApiError(fromQueryParams: params))))
            return
        }

        guard let params, let verificationCode = params.first(where: { $0.name == "verification_code" })?.value else {
            accountRecoveryCallback?(.failure(.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params))))
            return
        }

        guard let email = params.first(where: { $0.name == "email" })?.value else {
            accountRecoveryCallback?(.failure(.TechnicalError(reason: "No email", apiError: ApiError(fromQueryParams: params))))
            return
        }

        accountRecoveryCallback?(.success(AccountRecoveryResponse(email: email, verificationCode: verificationCode)))
    }
}
