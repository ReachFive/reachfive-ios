import Foundation
import BrightFutures

public extension ReachFive {
    func getProfile(authToken: AuthToken) -> Future<Profile, ReachFiveError> {
        reachFiveApi.getProfile(authToken: authToken)
    }

    func verifyPhoneNumber(
        authToken: AuthToken,
        phoneNumber: String,
        verificationCode: String
    ) -> Future<(), ReachFiveError> {
        let verifyPhoneNumberRequest = VerifyPhoneNumberRequest(
            phoneNumber: phoneNumber,
            verificationCode: verificationCode
        )
        return reachFiveApi
            .verifyPhoneNumber(authToken: authToken, verifyPhoneNumberRequest: verifyPhoneNumberRequest)
    }

    func updateEmail(
        authToken: AuthToken,
        email: String,
        redirectUrl: String? = nil
    ) -> Future<Profile, ReachFiveError> {
        let updateEmailRequest = UpdateEmailRequest(email: email, redirectUrl: redirectUrl)
        return reachFiveApi.updateEmail(
            authToken: authToken,
            updateEmailRequest: updateEmailRequest
        )
    }

    func updatePhoneNumber(
        authToken: AuthToken,
        phoneNumber: String
    ) -> Future<Profile, ReachFiveError> {
        let updatePhoneNumberRequest = UpdatePhoneNumberRequest(phoneNumber: phoneNumber)
        return reachFiveApi.updatePhoneNumber(
            authToken: authToken,
            updatePhoneNumberRequest: updatePhoneNumberRequest
        )
    }

    func updateProfile(
        authToken: AuthToken,
        profile: Profile
    ) -> Future<Profile, ReachFiveError> {
        reachFiveApi.updateProfile(authToken: authToken, profile: profile)
    }

    func updateProfile(
        authToken: AuthToken,
        profileUpdate: ProfileUpdate
    ) -> Future<Profile, ReachFiveError> {
        reachFiveApi.updateProfile(authToken: authToken, profileUpdate: profileUpdate)
    }

    func updatePassword(_ updatePasswordParams: UpdatePasswordParams) -> Future<(), ReachFiveError> {
        let authToken = updatePasswordParams.getAuthToken()
        return reachFiveApi.updatePassword(
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
    ) -> Future<(), ReachFiveError> {
        let requestPasswordResetRequest = RequestPasswordResetRequest(
            clientId: sdkConfig.clientId,
            email: email,
            phoneNumber: phoneNumber,
            redirectUrl: redirectUrl
        )
        return reachFiveApi.requestPasswordReset(
            requestPasswordResetRequest: requestPasswordResetRequest
        )
    }

    func requestAccountRecovery(
        email: String? = nil,
        phoneNumber: String? = nil,
        redirectUrl: String? = nil,
        origin: String? = nil
    ) -> Future<(), ReachFiveError> {
        let requestAccountRecoveryRequest = RequestAccountRecoveryRequest(
            clientId: sdkConfig.clientId,
            email: email,
            phoneNumber: phoneNumber,
            redirectUrl: redirectUrl ?? sdkConfig.accountRecoveryUri,
            origin: origin
        )
        return reachFiveApi.requestAccountRecovery(requestAccountRecoveryRequest)
    }

    /// Lists all passkeys the user has registered
    func listWebAuthnCredentials(authToken: AuthToken) -> Future<[DeviceCredential], ReachFiveError> {
        reachFiveApi.getWebAuthnRegistrations(authToken: authToken)
    }

    /// Deletes a passkey the user has registered
    func deleteWebAuthnRegistration(id: String, authToken: AuthToken) -> Future<(), ReachFiveError> {
        reachFiveApi.deleteWebAuthnRegistration(id: id, authToken: authToken)
    }

    func addAccountRecoveryCallback(accountRecoveryCallback: @escaping AccountRecoveryCallback) {
        self.accountRecoveryCallback = accountRecoveryCallback
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
