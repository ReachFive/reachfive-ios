import DeviceKit
import Foundation

public class ReachFiveApi {
    let sdkConfig: SdkConfig

    private let networkClient: NetworkClient

    private let profile_fields = [
        "birthdate",
        "bio",
        "middle_name",
        "addresses",
        "auth_types",
        "consents",
        "created_at",
        "custom_fields",
        "devices",
        "company",
        "email",
        "emails",
        "email_verified",
        "external_id",
        "family_name",
        "first_login",
        "first_name",
        "full_name",
        "gender",
        "given_name",
        "has_managed_profile",
        "has_password",
        "id",
        "identities",
        "last_login",
        "last_login_provider",
        "last_login_type",
        "last_name",
        "likes_friends_ratio",
        "lite_only",
        "locale",
        "local_friends_count",
        "login_summary",
        "logins_count",
        "name",
        "nickname",
        "origins",
        "picture",
        "phone_number",
        "phone_number_verified",
        "custom_identifier",
        "provider_details",
        "providers",
        "social_identities",
        "sub",
        "uid",
        "updated_at",
    ]

    public init(sdkConfig: SdkConfig) {
        self.sdkConfig = sdkConfig
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.networkClient = NetworkClient(decoder: decoder)
    }

    func createUrl(path: String, params: [String: String?]? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sdkConfig.domain
        components.path = path.starts(with: "/") ? path : "/" + path

        let deviceInfo: String = [Device.current.safeDescription, Device.current.systemName, Device.current.systemVersion].compactMap { $0 }.joined(separator: " ")
        let defaultParams: [String: String] = [
            "platform": "ios",
            // TODO: read from the version.rb. Either directly or indirectly from Reach5.h, Info.plist...
            "sdk": "8.2.0",
            "device": deviceInfo,
        ]

        let additionalParams = filter(params: params ?? [:])
        let allParams: [String: String] = defaultParams.merging(additionalParams) { current, _ in current }

        components.queryItems = allParams.map { key, value in URLQueryItem(name: key, value: value) }
        // safe force-unwrap because the contract is respected:
        // If the NSURLComponents has an authority component (user, password, host or port) and a path component, then the path must either begin with "/" or be an empty string.
        return components.url!
    }

    /// Keep only non-nil values
    private func filter(params: [String: String?]) -> [String: String] {
        params.compactMapValues { $0 }
    }

    public func clientConfig() async throws -> ClientConfigResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/config", params: ["client_id": sdkConfig.clientId]))
            .responseJson(type: ClientConfigResponse.self)
    }

    public func providersConfigs(variants: [String: String?]) async throws -> ProvidersConfigsResult {
        try await networkClient.request(createUrl(path: "/api/v1/providers", params: variants))
            .responseJson(type: ProvidersConfigsResult.self)
    }

    public func loginWithProvider(
        loginProviderRequest: LoginProviderRequest
    ) async throws -> AccessTokenResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/oauth/provider/token"), method: .post, parameters: loginProviderRequest.dictionary())
            .responseJson(type: AccessTokenResponse.self)
    }

    public func signupWithPassword(signupRequest: SignupRequest) async throws -> AccessTokenResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/signup-token"), method: .post, parameters: signupRequest.dictionary())
            .responseJson(type: AccessTokenResponse.self)
    }

    public func loginWithPassword(loginRequest: LoginRequest) async throws -> TknMfa {
        try await networkClient.request(createUrl(path: "/identity/v1/password/login"), method: .post, parameters: loginRequest.dictionary())
            .responseJson(type: TknMfa.self)
    }

    public func loginCallback(loginCallback: LoginCallback) async throws -> String {
        try await authorize(params: loginCallback.dictionary() as? [String: String])
    }

    public func authorize(params: [String: String?]?) async throws -> String {
        let url = try await networkClient.request(createUrl(path: "/oauth/authorize", params: params)).redirect()

        let params = URLComponents(string: url.absoluteString)?.queryItems
        let code = params?.first(where: { $0.name == "code" })?.value
        guard let code else {
            throw ReachFiveError.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params))
        }
        return code
    }

    public func authWithCode(authCodeRequest: AuthCodeRequest) async throws -> AccessTokenResponse {
        try await networkClient.request(createUrl(path: "/oauth/token"), method: .post, parameters: authCodeRequest.dictionary())
            .responseJson(type: AccessTokenResponse.self)
    }

    public func refreshAccessToken(_ refreshRequest: RefreshRequest) async throws -> AccessTokenResponse {
        try await networkClient.request(createUrl(path: "/oauth/token"), method: .post, parameters: refreshRequest.dictionary())
            .responseJson(type: AccessTokenResponse.self)
    }

    public func getProfile(authToken: AuthToken) async throws -> Profile {
        try await networkClient.request(createUrl(path: "/identity/v1/userinfo", params: ["fields": profile_fields.joined(separator: ","), "flatcf": "true"]), headers: tokenHeader(authToken))
            .responseJson(type: Profile.self)
    }

    public func sendEmailVerification(
        authToken: AuthToken,
        sendEmailVerificationRequest: SendEmailVerificationRequest
    ) async throws -> SendEmailVerificationResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/send-email-verification"), method: .post, headers: tokenHeader(authToken), parameters: sendEmailVerificationRequest.dictionary())
            .responseJson(type: SendEmailVerificationResponse.self)
    }

    public func verifyEmail(
        authToken: AuthToken,
        verifyEmailRequest: VerifyEmailRequest
    ) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/verify-email"), method: .post, headers: tokenHeader(authToken), parameters: verifyEmailRequest.dictionary())
            .responseJson()
    }

    public func verifyPhoneNumber(
        authToken: AuthToken,
        verifyPhoneNumberRequest: VerifyPhoneNumberRequest
    ) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/verify-phone-number"), method: .post, headers: tokenHeader(authToken), parameters: verifyPhoneNumberRequest.dictionary())
            .responseJson()
    }

    public func updateEmail(
        authToken: AuthToken,
        updateEmailRequest: UpdateEmailRequest
    ) async throws -> Profile {
        try await networkClient.request(createUrl(path: "/identity/v1/update-email"), method: .post, headers: tokenHeader(authToken), parameters: updateEmailRequest.dictionary())
            .responseJson(type: Profile.self)
    }

    public func updateProfile(
        authToken: AuthToken,
        profile: Profile
    ) async throws -> Profile {
        try await networkClient.request(createUrl(path: "/identity/v1/update-profile"), method: .post, headers: tokenHeader(authToken), parameters: profile.dictionary())
            .responseJson(type: Profile.self)
    }

    public func updateProfile(
        authToken: AuthToken,
        profileUpdate: ProfileUpdate
    ) async throws -> Profile {
        try await networkClient.request(createUrl(path: "/identity/v1/update-profile"), method: .post, headers: tokenHeader(authToken), parameters: profileUpdate.dictionary())
            .responseJson(type: Profile.self)
    }

    public func updatePassword(
        authToken: AuthToken?,
        updatePasswordRequest: UpdatePasswordRequest
    ) async throws {
        let headers: [String: String] = authToken.map { tokenHeader($0) } ?? [:]
        try await networkClient.request(createUrl(path: "/identity/v1/update-password"), method: .post, headers: headers, parameters: updatePasswordRequest.dictionary())
            .responseJson()
    }

    public func updatePhoneNumber(
        authToken: AuthToken,
        updatePhoneNumberRequest: UpdatePhoneNumberRequest
    ) async throws -> Profile {
        try await networkClient.request(createUrl(path: "/identity/v1/update-phone-number"), method: .post, headers: tokenHeader(authToken), parameters: updatePhoneNumberRequest.dictionary())
            .responseJson(type: Profile.self)
    }

    public func startMfaPhoneRegistration(
        _ mfaStartPhoneRegistrationRequest: MfaStartPhoneRegistrationRequest,
        authToken: AuthToken
    ) async throws -> MfaStartCredentialRegistrationResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/credentials/phone-numbers"), method: .post, headers: tokenHeader(authToken), parameters: mfaStartPhoneRegistrationRequest.dictionary())
            .responseJson(type: MfaStartCredentialRegistrationResponse.self)
    }

    public func startMfaEmailRegistration(
        _ mfaStartEmailRegistrationRequest: MfaStartEmailRegistrationRequest,
        authToken: AuthToken
    ) async throws -> MfaStartCredentialRegistrationResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/credentials/emails"), method: .post, headers: tokenHeader(authToken), parameters: mfaStartEmailRegistrationRequest.dictionary())
            .responseJson(type: MfaStartCredentialRegistrationResponse.self)
    }

    public func verifyMfaEmailRegistrationPost(
        _ mfaVerifyEmailRegistrationRequest: MfaVerifyEmailRegistrationPostRequest,
        authToken: AuthToken
    ) async throws -> MfaCredentialItem {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/credentials/emails/verify"), method: .post, headers: tokenHeader(authToken), parameters: mfaVerifyEmailRegistrationRequest.dictionary())
            .responseJson(type: MfaCredentialItem.self)
    }

    public func verifyMfaEmailRegistrationGet(
        _ request: MfaVerifyEmailRegistrationGetRequest
    ) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/credentials/emails/verify"), method: .post, parameters: request.dictionary())
            .responseJson()
    }

    public func verifyMfaPhoneRegistration(
        _ mfaVerifyPhoneRegistrationRequest: MfaVerifyPhoneRegistrationRequest,
        authToken: AuthToken
    ) async throws -> MfaCredentialItem {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/credentials/phone-numbers/verify"), method: .post, headers: tokenHeader(authToken), parameters: mfaVerifyPhoneRegistrationRequest.dictionary())
            .responseJson(type: MfaCredentialItem.self)
    }

    public func deleteMfaPhoneNumberCredential(
        phoneNumber: String,
        authToken: AuthToken
    ) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/credentials/phone-numbers"), method: .delete, headers: tokenHeader(authToken), parameters: ["phone_number": phoneNumber])
            .responseJson()
    }

    public func deleteMfaEmailCredential(
        authToken: AuthToken
    ) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/credentials/emails"), method: .delete, headers: tokenHeader(authToken))
            .responseJson()
    }

    public func listMfaTrustedDevices(
        authToken: AuthToken
    ) async throws -> MfaListTrustedDevices {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/trusteddevices"), headers: tokenHeader(authToken))
            .responseJson(type: MfaListTrustedDevices.self)
    }

    public func deleteMfaTrustedDevice(
        deviceId: String,
        authToken: AuthToken
    ) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/trusteddevices/\(deviceId)"), method: .delete, headers: tokenHeader(authToken))
            .responseJson()
    }

    public func mfaListCredentials(
        authToken: AuthToken
    ) async throws -> MfaCredentialsListResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/credentials"), headers: tokenHeader(authToken))
            .responseJson(type: MfaCredentialsListResponse.self)
    }

    public func startMfaStepUp(
        _ request: StartMfaStepUpRequest,
        authToken: AuthToken? = nil
    ) async throws -> StartMfaStepUpResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/mfa/stepup"), method: .post, headers: authToken.map(tokenHeader), parameters: request.dictionary())
            .responseJson(type: StartMfaStepUpResponse.self)
    }

    public func startPasswordless(mfa request: StartMfaPasswordlessRequest) async throws -> StartMfaPasswordlessResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/passwordless/start"), method: .post, parameters: request.dictionary())
            .responseJson(type: StartMfaPasswordlessResponse.self)
    }

    public func verifyPasswordless(mfa request: VerifyMfaPasswordlessRequest) async throws -> PasswordlessVerifyResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/passwordless/verify"), method: .post, parameters: request.dictionary())
            .responseJson(type: PasswordlessVerifyResponse.self)
    }

    public func requestPasswordReset(
        requestPasswordResetRequest: RequestPasswordResetRequest
    ) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/forgot-password"), method: .post, parameters: requestPasswordResetRequest.dictionary())
            .responseJson()
    }

    public func requestAccountRecovery(
        _ requestAccountRecoveryRequest: RequestAccountRecoveryRequest
    ) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/account-recovery"), method: .post, parameters: requestAccountRecoveryRequest.dictionary())
            .responseJson()
    }

    public func startPasswordless(_ startPasswordlessRequest: StartPasswordlessRequest) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/passwordless/start"), method: .post, parameters: startPasswordlessRequest.dictionary())
            .responseJson()
    }

    public func verifyPasswordless(verifyPasswordlessRequest: VerifyPasswordlessRequest) async throws -> PasswordlessVerifyResponse {
        try await networkClient.request(createUrl(path: "/identity/v1/passwordless/verify"), method: .post, parameters: verifyPasswordlessRequest.dictionary())
            .responseJson(type: PasswordlessVerifyResponse.self)
    }

    public func verifyAuthCode(verifyAuthCodeRequest: VerifyAuthCodeRequest) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/verify-auth-code"), method: .post, parameters: verifyAuthCodeRequest.dictionary())
            .responseJson()
    }

    public func logout() async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/logout"))
            .responseJson()
    }

    func tokenHeader(_ authToken: AuthToken) -> [String: String] {
       ["Authorization": "\(authToken.tokenType ?? "Bearer") \(authToken.accessToken)"]
    }

    public func buildAuthorizeURL(queryParams: [String: String?]) -> URL {
        createUrl(path: "/oauth/authorize", params: queryParams)
    }

    public func createWebAuthnSignupOptions(webAuthnSignupOptions: SignupOptions) async throws -> RegistrationOptions {
        try await networkClient.request(createUrl(path: "/identity/v1/webauthn/signup-options"), method: .post, parameters: webAuthnSignupOptions.dictionary())
            .responseJson(type: RegistrationOptions.self)
    }

    public func signupWithWebAuthn(webauthnSignupCredential: WebauthnSignupCredential, originR5: String? = nil) async throws -> AuthenticationToken {
        try await networkClient.request(createUrl(path: "/identity/v1/webauthn/signup", params: ["origin": originR5]), method: .post, parameters: webauthnSignupCredential.dictionary())
            .responseJson(type: AuthenticationToken.self)
    }

    public func createWebAuthnAuthenticationOptions(webAuthnLoginRequest: WebAuthnLoginRequest) async throws -> AuthenticationOptions {
        try await networkClient.request(createUrl(path: "/identity/v1/webauthn/authentication-options"), method: .post, parameters: webAuthnLoginRequest.dictionary())
            .responseJson(type: AuthenticationOptions.self)
    }

    public func authenticateWithWebAuthn(authenticationPublicKeyCredential: AuthenticationPublicKeyCredential) async throws -> AuthenticationToken {
        try await networkClient.request(createUrl(path: "/identity/v1/webauthn/authentication"), method: .post, parameters: authenticationPublicKeyCredential.dictionary())
            .responseJson(type: AuthenticationToken.self)
    }

    public func createWebAuthnRegistrationOptions(authToken: AuthToken, registrationRequest: RegistrationRequest) async throws -> RegistrationOptions {
        try await networkClient.request(createUrl(path: "/identity/v1/webauthn/registration-options"), method: .post, headers: tokenHeader(authToken), parameters: registrationRequest.dictionary())
            .responseJson(type: RegistrationOptions.self)
    }

    public func registerWithWebAuthn(authToken: AuthToken, publicKeyCredential: RegistrationPublicKeyCredential, originR5: String? = nil) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/webauthn/registration", params: ["origin": originR5]), method: .post, headers: tokenHeader(authToken), parameters: publicKeyCredential.dictionary())
            .responseJson()
    }

    public func createWebAuthnResetOptions(resetOptions: ResetOptions) async throws -> RegistrationOptions {
        try await networkClient.request(createUrl(path: "/identity/v1/webauthn/reset-options"), method: .post, parameters: resetOptions.dictionary())
            .responseJson(type: RegistrationOptions.self)
    }

    public func resetWebAuthn(resetPublicKeyCredential: ResetPublicKeyCredential, originR5: String? = nil) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/webauthn/reset", params: ["origin": originR5]), method: .post, parameters: resetPublicKeyCredential.dictionary())
            .responseJson()
    }

    public func getWebAuthnRegistrations(authToken: AuthToken) async throws -> [DeviceCredential] {
        try await networkClient.request(createUrl(path: "/identity/v1/webauthn/registration"), headers: tokenHeader(authToken))
            .responseJson(type: [DeviceCredential].self)
    }

    public func deleteWebAuthnRegistration(id: String, authToken: AuthToken) async throws {
        try await networkClient.request(createUrl(path: "/identity/v1/webauthn/registration/\(id)"), method: .delete, headers: tokenHeader(authToken))
            .responseJson()
    }
}

struct EmptyResponse: Decodable {}

enum HttpMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
    case put = "PUT"
}
