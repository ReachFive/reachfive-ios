import Foundation


public class ContinueEmailVerification {
    private let reachfive: ReachFive
    private let authToken: AuthToken

    fileprivate init(reachFive: ReachFive, authToken: AuthToken) {
        self.authToken = authToken
        self.reachfive = reachFive
    }

    public func verify(code: String, email: String, freshAuthToken: AuthToken? = nil) async throws -> Void {
        let userAuthToken = freshAuthToken ?? self.authToken
        let verifyEmailRequest = VerifyEmailRequest(email: email, verificationCode: code)
        return await self.reachfive.reachFiveApi.verifyEmail(authToken: userAuthToken, verifyEmailRequest: verifyEmailRequest)
    }
}

public enum EmailVerificationResponse {
    case Success
    case VerificationNeeded(_ continueEmailVerification: ContinueEmailVerification)
}

public extension ReachFive {
    func getProfile(authToken: AuthToken) async throws -> Profile {
        await reachFiveApi.getProfile(authToken: authToken)
    }

    func sendEmailVerification(authToken: AuthToken, redirectUrl: String? = nil) async throws -> EmailVerificationResponse{
        let sendEmailVerificationRequest = SendEmailVerificationRequest(redirectUrl: redirectUrl ?? sdkConfig.emailVerificationUri)

        return await reachFiveApi
            .sendEmailVerification(authToken: authToken, sendEmailVerificationRequest: sendEmailVerificationRequest)
            .map { resp in
                switch resp.verificationEmailSent {
                case false: .Success
                case true : .VerificationNeeded(ContinueEmailVerification(reachFive: self, authToken: authToken))
                }
            }
    }

    func verifyEmail(authToken: AuthToken, code: String, email: String) async throws -> Void {
        let verifyEmailRequest = VerifyEmailRequest(email: email, verificationCode: code)

        return await reachFiveApi.verifyEmail(authToken: authToken, verifyEmailRequest: verifyEmailRequest)
    }

    func verifyPhoneNumber(
        authToken: AuthToken,
        phoneNumber: String,
        verificationCode: String
    ) async -> Result<(), ReachFiveError> {
        let verifyPhoneNumberRequest = VerifyPhoneNumberRequest(
            phoneNumber: phoneNumber,
            verificationCode: verificationCode
        )
        return await reachFiveApi
            .verifyPhoneNumber(authToken: authToken, verifyPhoneNumberRequest: verifyPhoneNumberRequest)
    }

    func updateEmail(
        authToken: AuthToken,
        email: String,
        redirectUrl: String? = nil
    ) async throws -> Profile {
        let updateEmailRequest = UpdateEmailRequest(email: email, redirectUrl: redirectUrl)
        return await reachFiveApi.updateEmail(
            authToken: authToken,
            updateEmailRequest: updateEmailRequest
        )
    }

    func updatePhoneNumber(
        authToken: AuthToken,
        phoneNumber: String
    ) async throws -> Profile {
        let updatePhoneNumberRequest = UpdatePhoneNumberRequest(phoneNumber: phoneNumber)
        return await reachFiveApi.updatePhoneNumber(
            authToken: authToken,
            updatePhoneNumberRequest: updatePhoneNumberRequest
        )
    }

    func updateProfile(
        authToken: AuthToken,
        profile: Profile
    ) async throws -> Profile {
        await reachFiveApi.updateProfile(authToken: authToken, profile: profile)
    }

    func updateProfile(
        authToken: AuthToken,
        profileUpdate: ProfileUpdate
    ) async throws -> Profile {
        await reachFiveApi.updateProfile(authToken: authToken, profileUpdate: profileUpdate)
    }

    func updatePassword(_ updatePasswordParams: UpdatePasswordParams) async -> Result<(), ReachFiveError> {
        let authToken = updatePasswordParams.getAuthToken()
        return await reachFiveApi.updatePassword(
            authToken: authToken,
            updatePasswordRequest: UpdatePasswordRequest(
                updatePasswordParams: updatePasswordParams,
                sdkConfig: sdkConfig
            )
        )
    }

    func requestPasswordReset(
        email: String? = nil,
        phoneNumber: String? = nil,
        redirectUrl: String? = nil
    ) async -> Result<(), ReachFiveError> {
        let requestPasswordResetRequest = RequestPasswordResetRequest(
            clientId: sdkConfig.clientId,
            email: email,
            phoneNumber: phoneNumber,
            redirectUrl: redirectUrl
        )
        return await reachFiveApi.requestPasswordReset(
            requestPasswordResetRequest: requestPasswordResetRequest
        )
    }

    func requestAccountRecovery(
        email: String? = nil,
        phoneNumber: String? = nil,
        redirectUrl: String? = nil,
        origin: String? = nil
    ) async -> Result<(), ReachFiveError> {
        let requestAccountRecoveryRequest = RequestAccountRecoveryRequest(
            clientId: sdkConfig.clientId,
            email: email,
            phoneNumber: phoneNumber,
            redirectUrl: redirectUrl ?? sdkConfig.accountRecoveryUri,
            origin: origin
        )
        return await reachFiveApi.requestAccountRecovery(requestAccountRecoveryRequest)
    }

    /// Lists all passkeys the user has registered
    func listWebAuthnCredentials(authToken: AuthToken) async throws -> [DeviceCredential] {
        await reachFiveApi.getWebAuthnRegistrations(authToken: authToken)
    }

    /// Deletes a passkey the user has registered
    func deleteWebAuthnRegistration(id: String, authToken: AuthToken) async -> Result<(), ReachFiveError> {
        await reachFiveApi.deleteWebAuthnRegistration(id: id, authToken: authToken)
    }

    func addAccountRecoveryCallback(accountRecoveryCallback: @escaping AccountRecoveryCallback) {
        self.accountRecoveryCallback = accountRecoveryCallback
    }

    func addEmailVerificationCallback(emailVerificationCallback: @escaping EmailVerificationCallback) {
        self.emailVerificationCallback = emailVerificationCallback
    }

    func interceptEmailVerification(_ url: URL) {
        let params = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems
        if let error = params?.first(where: { $0.name == "error" })?.value {
            emailVerificationCallback?(.failure(.TechnicalError(reason: error, apiError: ApiError(fromQueryParams: params))))
            return
        }
        emailVerificationCallback?(.success(()))
    }

    func interceptAccountRecovery(_ url: URL) {
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
