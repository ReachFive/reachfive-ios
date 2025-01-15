import Alamofire
import BrightFutures
import DeviceKit
import Foundation

public class ReachFiveApi {
    let decoder = JSONDecoder()
    let sdkConfig: SdkConfig

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
        decoder.keyDecodingStrategy = .convertFromSnakeCase
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
            "sdk": "8.0.0",
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

    public func clientConfig() -> Future<ClientConfigResponse, ReachFiveError> {
        AF
            .request(createUrl(path: "/identity/v1/config", params: ["client_id": sdkConfig.clientId]))
            .validate(contentType: ["application/json"])
            .responseJson(type: ClientConfigResponse.self, decoder: decoder)
    }

    public func providersConfigs(variants: [String: String?]) -> Future<ProvidersConfigsResult, ReachFiveError> {
        AF
            .request(createUrl(path: "/api/v1/providers", params: variants))
            .validate(contentType: ["application/json"])
            .responseJson(type: ProvidersConfigsResult.self, decoder: decoder)
    }

    public func loginWithProvider(
        loginProviderRequest: LoginProviderRequest
    ) -> Future<AccessTokenResponse, ReachFiveError> {
        AF
            .request(createUrl(path: "/identity/v1/oauth/provider/token"),
                method: .post,
                parameters: loginProviderRequest.dictionary(),
                encoding: JSONEncoding.default)
            .validate(contentType: ["application/json"])
            .responseJson(type: AccessTokenResponse.self, decoder: decoder)
    }

    public func signupWithPassword(signupRequest: SignupRequest) -> Future<AccessTokenResponse, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/signup-token"),
                method: .post,
                parameters: signupRequest.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: AccessTokenResponse.self, decoder: decoder)
    }

    public func loginWithPassword(loginRequest: LoginRequest) -> Future<TknMfa, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/password/login"),
                method: .post,
                parameters: loginRequest.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: TknMfa.self, decoder: decoder)
    }

    public func loginCallback(loginCallback: LoginCallback) -> Future<String, ReachFiveError> {
        authorize(params: loginCallback.dictionary() as? [String: String])
    }

    public func authorize(params: [String: String?]?) -> Future<String, ReachFiveError> {
        let promise = Promise<String, ReachFiveError>()

        AF
            .request(
                createUrl(path: "/oauth/authorize", params: params),
                method: .get
            )
            .redirect(using: Redirector.doNotFollow)
            .validate(statusCode: 300...308) //TODO pas de 305/306
            .response { responseData in
                let callbackURL = responseData.response?.allHeaderFields["Location"] as? String
                guard let callbackURL else {
                    promise.failure(.TechnicalError(reason: "No location"))
                    return
                }
                let params = URLComponents(string: callbackURL)?.queryItems
                let code = params?.first(where: { $0.name == "code" })?.value
                guard let code else {
                    promise.tryFailure(.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params)))
                    return
                }
                promise.success(code)
            }
        return promise.future
    }

    public func authWithCode(authCodeRequest: AuthCodeRequest) -> Future<AccessTokenResponse, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/oauth/token"),
                method: .post,
                parameters: authCodeRequest.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: AccessTokenResponse.self, decoder: decoder)
    }

    public func refreshAccessToken(_ refreshRequest: RefreshRequest) -> Future<AccessTokenResponse, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/oauth/token"),
                method: .post,
                parameters: refreshRequest.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: AccessTokenResponse.self, decoder: decoder)
    }

    public func getProfile(authToken: AuthToken) -> Future<Profile, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/userinfo", params: ["fields": profile_fields.joined(separator: ",")]),
                method: .get,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: Profile.self, decoder: decoder)
    }

    public func verifyPhoneNumber(
        authToken: AuthToken,
        verifyPhoneNumberRequest: VerifyPhoneNumberRequest
    ) -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/verify-phone-number"),
                method: .post,
                parameters: verifyPhoneNumberRequest.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }

    public func updateEmail(
        authToken: AuthToken,
        updateEmailRequest: UpdateEmailRequest
    ) -> Future<Profile, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/update-email"),
                method: .post,
                parameters: updateEmailRequest.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: Profile.self, decoder: decoder)
    }

    public func updateProfile(
        authToken: AuthToken,
        profile: Profile
    ) -> Future<Profile, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/update-profile"),
                method: .post,
                parameters: profile.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: Profile.self, decoder: decoder)
    }

    public func updateProfile(
        authToken: AuthToken,
        profileUpdate: ProfileUpdate
    ) -> Future<Profile, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/update-profile"),
                method: .post,
                parameters: profileUpdate.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: Profile.self, decoder: decoder)
    }

    public func updatePassword(
        authToken: AuthToken?,
        updatePasswordRequest: UpdatePasswordRequest
    ) -> Future<Void, ReachFiveError> {
        let headers: HTTPHeaders = authToken != nil ? tokenHeader(authToken!) : [:]
        return AF
            .request(
                createUrl(path: "/identity/v1/update-password"),
                method: .post,
                parameters: updatePasswordRequest.dictionary(),
                encoding: JSONEncoding.default,
                headers: headers
            )
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }

    public func updatePhoneNumber(
        authToken: AuthToken,
        updatePhoneNumberRequest: UpdatePhoneNumberRequest
    ) -> Future<Profile, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/update-phone-number"),
                method: .post,
                parameters: updatePhoneNumberRequest.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: Profile.self, decoder: decoder)
    }

    public func startMfaPhoneRegistration(
        _ mfaStartPhoneRegistrationRequest: MfaStartPhoneRegistrationRequest,
        authToken: AuthToken
    ) -> Future<MfaStartCredentialRegistrationResponse, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/credentials/phone-numbers"),
                method: .post,
                parameters: mfaStartPhoneRegistrationRequest.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: MfaStartCredentialRegistrationResponse.self, decoder: decoder)
    }

    public func startMfaEmailRegistration(
        _ mfaStartEmailRegistrationRequest: MfaStartEmailRegistrationRequest,
        authToken: AuthToken
    ) -> Future<MfaStartCredentialRegistrationResponse, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/credentials/emails"),
                method: .post,
                parameters: mfaStartEmailRegistrationRequest.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: MfaStartCredentialRegistrationResponse.self, decoder: decoder)
    }

    public func verifyMfaEmailRegistrationPost(
        _ mfaVerifyEmailRegistrationRequest: MfaVerifyEmailRegistrationPostRequest,
        authToken: AuthToken
    ) -> Future<MfaCredentialItem, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/credentials/emails/verify"),
                method: .post,
                parameters: mfaVerifyEmailRegistrationRequest.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: MfaCredentialItem.self, decoder: decoder)
    }

    public func verifyMfaEmailRegistrationGet(
        _ request: MfaVerifyEmailRegistrationGetRequest
    ) -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/credentials/emails/verify"),
                method: .post,
                parameters: request.dictionary(),
                encoding: URLEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }

    public func verifyMfaPhoneRegistration(
        _ mfaVerifyPhoneRegistrationRequest: MfaVerifyPhoneRegistrationRequest,
        authToken: AuthToken
    ) -> Future<MfaCredentialItem, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/credentials/phone-numbers/verify"),
                method: .post,
                parameters: mfaVerifyPhoneRegistrationRequest.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: MfaCredentialItem.self, decoder: decoder)
    }

    public func deleteMfaPhoneNumberCredential(
        phoneNumber: String,
        authToken: AuthToken
    ) -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/credentials/phone-numbers"),
                method: .delete,
                parameters: ["phone_number": phoneNumber],
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }

    public func deleteMfaEmailCredential(
        authToken: AuthToken
    ) -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/credentials/emails"),
                method: .delete,
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }

    public func listMfaTrustedDevices(
        authToken: AuthToken
    ) -> Future<MfaListTrustedDevices, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/trusteddevices"),
                method: .get,
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: MfaListTrustedDevices.self, decoder: decoder)
    }

    public func deleteMfaTrustedDevice(
        deviceId: String,
        authToken: AuthToken
    ) -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/trusteddevices/\(deviceId)"),
                method: .delete,
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }

    public func mfaListCredentials(
        authToken: AuthToken
    ) -> Future<MfaCredentialsListResponse, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/credentials"),
                method: .get,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: MfaCredentialsListResponse.self, decoder: decoder)
    }

    public func startMfaStepUp(
        _ request: StartMfaStepUpRequest,
        authToken: AuthToken? = nil
    ) -> Future<StartMfaStepUpResponse, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/mfa/stepup"),
                method: .post,
                parameters: request.dictionary(),
                encoding: JSONEncoding.default,
                headers: authToken.map(tokenHeader)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: StartMfaStepUpResponse.self, decoder: decoder)
    }

    public func startPasswordless(mfa request: StartMfaPasswordlessRequest) -> Future<StartMfaPasswordlessResponse, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/passwordless/start"),
                method: .post,
                parameters: request.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: StartMfaPasswordlessResponse.self, decoder: decoder)
    }

    public func verifyPasswordless(mfa request: VerifyMfaPasswordlessRequest) -> Future<PasswordlessVerifyResponse, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/passwordless/verify"),
                method: .post,
                parameters: request.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: PasswordlessVerifyResponse.self, decoder: decoder)
    }

    public func requestPasswordReset(
        requestPasswordResetRequest: RequestPasswordResetRequest
    ) -> Future<Void, ReachFiveError> {
        AF
            .request(createUrl(
                path: "/identity/v1/forgot-password"),
            method: .post,
            parameters: requestPasswordResetRequest.dictionary(),
            encoding: JSONEncoding.default)
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }

    public func requestAccountRecovery(
        _ requestAccountRecoveryRequest: RequestAccountRecoveryRequest
    ) -> Future<Void, ReachFiveError> {
        AF
            .request(createUrl(
                path: "/identity/v1/account-recovery"),
            method: .post,
            parameters: requestAccountRecoveryRequest.dictionary(),
            encoding: JSONEncoding.default)
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }

    public func startPasswordless(_ startPasswordlessRequest: StartPasswordlessRequest) -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/passwordless/start"),
                method: .post,
                parameters: startPasswordlessRequest.dictionary(),
                encoding: JSONEncoding.default
            )
            .responseJson(decoder: decoder)
    }

    public func verifyPasswordless(verifyPasswordlessRequest: VerifyPasswordlessRequest) -> Future<PasswordlessVerifyResponse, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/passwordless/verify"),
                method: .post,
                parameters: verifyPasswordlessRequest.dictionary()
            )
            .responseJson(type: PasswordlessVerifyResponse.self, decoder: decoder)
    }

    public func verifyAuthCode(verifyAuthCodeRequest: VerifyAuthCodeRequest) -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/verify-auth-code"),
                method: .post,
                parameters: verifyAuthCodeRequest.dictionary(),
                encoding: JSONEncoding.default
            )
            .responseJson(decoder: decoder)
    }

    public func logout() -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/logout"),
                method: .get
            )
            .responseJson(decoder: decoder)
    }

    func tokenHeader(_ authToken: AuthToken) -> HTTPHeaders {
       ["Authorization": "\(authToken.tokenType ?? "Bearer") \(authToken.accessToken)"]
    }

    public func buildAuthorizeURL(queryParams: [String: String?]) -> URL {
        createUrl(path: "/oauth/authorize", params: queryParams)
    }

    public func createWebAuthnSignupOptions(webAuthnSignupOptions: SignupOptions) -> Future<RegistrationOptions, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/webauthn/signup-options"),
                method: .post,
                parameters: webAuthnSignupOptions.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: RegistrationOptions.self, decoder: decoder)
    }

    public func signupWithWebAuthn(webauthnSignupCredential: WebauthnSignupCredential, originR5: String? = nil) -> Future<AuthenticationToken, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/webauthn/signup", params: ["origin": originR5]),
                method: .post,
                parameters: webauthnSignupCredential.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: AuthenticationToken.self, decoder: decoder)
    }

    public func createWebAuthnAuthenticationOptions(webAuthnLoginRequest: WebAuthnLoginRequest) -> Future<AuthenticationOptions, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/webauthn/authentication-options"),
                method: .post,
                parameters: webAuthnLoginRequest.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: AuthenticationOptions.self, decoder: decoder)
    }

    public func authenticateWithWebAuthn(authenticationPublicKeyCredential: AuthenticationPublicKeyCredential) -> Future<AuthenticationToken, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/webauthn/authentication"),
                method: .post,
                parameters: authenticationPublicKeyCredential.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: AuthenticationToken.self, decoder: decoder)
    }

    public func createWebAuthnRegistrationOptions(authToken: AuthToken, registrationRequest: RegistrationRequest) -> Future<RegistrationOptions, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/webauthn/registration-options"),
                method: .post,
                parameters: registrationRequest.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: RegistrationOptions.self, decoder: decoder)
    }

    public func registerWithWebAuthn(authToken: AuthToken, publicKeyCredential: RegistrationPublicKeyCredential, originR5: String? = nil) -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/webauthn/registration", params: ["origin": originR5]),
                method: .post,
                parameters: publicKeyCredential.dictionary(),
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }

    public func createWebAuthnResetOptions(resetOptions: ResetOptions) -> Future<RegistrationOptions, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/webauthn/reset-options"),
                method: .post,
                parameters: resetOptions.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: RegistrationOptions.self, decoder: decoder)
    }

    public func resetWebAuthn(resetPublicKeyCredential: ResetPublicKeyCredential, originR5: String? = nil) -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/webauthn/reset", params: ["origin": originR5]),
                method: .post,
                parameters: resetPublicKeyCredential.dictionary(),
                encoding: JSONEncoding.default
            )
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }

    public func getWebAuthnRegistrations(authToken: AuthToken) -> Future<[DeviceCredential], ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/webauthn/registration"),
                method: .get,
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(type: [DeviceCredential].self, decoder: decoder)
    }

    public func deleteWebAuthnRegistration(id: String, authToken: AuthToken) -> Future<Void, ReachFiveError> {
        AF
            .request(
                createUrl(path: "/identity/v1/webauthn/registration/\(id)"),
                method: .delete,
                encoding: JSONEncoding.default,
                headers: tokenHeader(authToken)
            )
            .validate(contentType: ["application/json"])
            .responseJson(decoder: decoder)
    }
}
