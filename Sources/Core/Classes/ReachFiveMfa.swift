import Foundation

public enum CredentialType {
    case Email
    case PhoneNumber
}

public enum Credential {
    case Email(redirectUrl: String? = nil)
    case PhoneNumber(_ phoneNumber: String)

    public var credentialType: CredentialType {
        switch self {
        case .Email: return CredentialType.Email
        case .PhoneNumber: return CredentialType.PhoneNumber
        }
    }
}

public enum StartStepUp {
    case AuthTokenFlow(authType: MfaCredentialItemType, authToken: AuthToken, redirectUri: String? = nil, scope: [String]? = nil, origin: String? = nil, action: String? = nil)
    case LoginFlow(authType: MfaCredentialItemType, stepUpToken: String, redirectUri: String? = nil, origin: String? = nil)
    public var authType: MfaCredentialItemType {
        switch self {
        case let .AuthTokenFlow(authType, _, _, _, _, _): return authType
        case let .LoginFlow(authType, _, _, _): return authType
        }
    }
}

public class ContinueStepUp {
    public let challengeId: String
    public let reachfive: ReachFive

    fileprivate init(challengeId: String, reachFive: ReachFive) {
        self.challengeId = challengeId
        self.reachfive = reachFive
    }

    public func verify(code: String, trustDevice: Bool? = nil) async throws -> AuthToken {
        try await reachfive.mfaVerify(stepUp: VerifyStepUp(challengeId: challengeId, verificationCode: code, trustDevice: trustDevice))
    }
}

public struct VerifyStepUp {
    var challengeId: String
    var verificationCode: String
    var trustDevice: Bool?

    public init(challengeId: String, verificationCode: String, trustDevice: Bool? = nil) {
        self.challengeId = challengeId
        self.verificationCode = verificationCode
        self.trustDevice = trustDevice
    }
}

public class ContinueRegistration {
    public let credentialType: CredentialType
    private let reachfive: ReachFive
    private let authToken: AuthToken

    fileprivate init(credentialType: CredentialType, reachfive: ReachFive, authToken: AuthToken) {
        self.credentialType = credentialType
        self.authToken = authToken
        self.reachfive = reachfive
    }

    public func verify(code: String, freshAuthToken: AuthToken? = nil) async throws -> MfaCredentialItem {
        try await reachfive.mfaVerify(credentialType, code: code, authToken: freshAuthToken ?? authToken)
    }
}

public enum MfaStartRegistrationResponse {
    case Success(_ success: MfaCredentialItem)
    case VerificationNeeded(_ continueRegistration: ContinueRegistration)
}

public extension ReachFive {
    func addMfaCredentialRegistrationCallback(mfaCredentialRegistrationCallback: @escaping MfaCredentialRegistrationCallback) {
        self.mfaCredentialRegistrationCallback = mfaCredentialRegistrationCallback
    }

    func mfaStart(registering credential: Credential, authToken: AuthToken, action: String? = nil) async throws -> MfaStartRegistrationResponse {
        let registration =
            switch credential {
            case let .Email(redirectUrl):
                try await reachFiveApi.startMfaEmailRegistration(MfaStartEmailRegistrationRequest(redirectUrl: redirectUrl ?? sdkConfig.mfaUri, action: action), authToken: authToken)
            case let .PhoneNumber(phoneNumber):
                try await reachFiveApi.startMfaPhoneRegistration(MfaStartPhoneRegistrationRequest(phoneNumber: phoneNumber, action: action), authToken: authToken)
            }

        if let credential = registration.credential, registration.status == "enabled" {
            return .Success(credential)
        }
        return .VerificationNeeded(ContinueRegistration(credentialType: credential.credentialType, reachfive: self, authToken: authToken))
    }

    func mfaVerify(_ credentialType: CredentialType, code: String, authToken: AuthToken) async throws -> MfaCredentialItem {
        switch credentialType {
        case .Email:
            let request = MfaVerifyEmailRegistrationPostRequest(code)
            return try await reachFiveApi.verifyMfaEmailRegistrationPost(request, authToken: authToken)
        case .PhoneNumber:
            let request = MfaVerifyPhoneRegistrationRequest(code)
            return try await reachFiveApi.verifyMfaPhoneRegistration(request, authToken: authToken)
        }
    }

    func mfaListCredentials(authToken: AuthToken) async throws -> MfaCredentialsListResponse {
        try await reachFiveApi.mfaListCredentials(authToken: authToken)
    }

    func mfaStart(stepUp request: StartStepUp) async throws -> ContinueStepUp {
        switch request {

        case let .LoginFlow(authType, stepUpToken, redirectUri, origin):
            let response = try await reachFiveApi.startPasswordless(mfa: StartMfaPasswordlessRequest(redirectUri: redirectUri ?? sdkConfig.redirectUri, clientId: sdkConfig.clientId, stepUp: stepUpToken, authType: authType, origin: origin))
            return ContinueStepUp(challengeId: response.challengeId, reachFive: self)

        case let .AuthTokenFlow(authType, authToken, redirectUri, overwrittenScope, origin, action):
            let pkce = Pkce.generate()
            storage.save(key: pkceKey, value: pkce)
            let stepUp = StartMfaStepUpRequest(clientId: sdkConfig.clientId, redirectUri: redirectUri ?? sdkConfig.redirectUri, pkce: pkce, scope: (overwrittenScope ?? scope).joined(separator: " "), action: action)
            let result = try await reachFiveApi.startMfaStepUp(stepUp, authToken: authToken)
            let response = try await self.reachFiveApi.startPasswordless(mfa: StartMfaPasswordlessRequest(redirectUri: redirectUri ?? self.sdkConfig.redirectUri, clientId: self.sdkConfig.clientId, stepUp: result.token, authType: authType, origin: origin))
            return ContinueStepUp(challengeId: response.challengeId, reachFive: self)
        }
    }

    func mfaVerify(stepUp request: VerifyStepUp) async throws -> AuthToken {
        let pkce: Pkce? = storage.get(key: pkceKey)
        guard let pkce else {
            throw ReachFiveError.TechnicalError(reason: "Pkce not found")
        }
        let response = try await reachFiveApi.verifyPasswordless(mfa: VerifyMfaPasswordlessRequest(challengeId: request.challengeId, verificationCode: request.verificationCode, trustDevice: request.trustDevice))
        guard let code = response.code else {
            throw ReachFiveError.TechnicalError(reason: "No authorization code")
        }
        return try await self.authWithCode(code: code, pkce: pkce)
    }

    func mfaDeleteCredential(_ phoneNumber: String? = nil, authToken: AuthToken) async throws {
        if let phoneNumber {
            return try await reachFiveApi.deleteMfaPhoneNumberCredential(phoneNumber: phoneNumber, authToken: authToken)
        }
        return try await reachFiveApi.deleteMfaEmailCredential(authToken: authToken)
    }

    func mfaListTrustedDevices(authToken: AuthToken) async throws -> [TrustedDevice] {
        try await reachFiveApi
            .listMfaTrustedDevices(authToken: authToken)
            .trustedDevices
    }

    func mfaDelete(trustedDeviceId deviceId: String, authToken: AuthToken) async throws {
        try await reachFiveApi.deleteMfaTrustedDevice(deviceId: deviceId, authToken: authToken)
    }

    internal func interceptVerifyMfaCredential(_ url: URL) {
        let params = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems
        if let error = params?.first(where: { $0.name == "error" })?.value {
            mfaCredentialRegistrationCallback?(.failure(.TechnicalError(reason: error, apiError: ApiError(fromQueryParams: params))))
            return
        }

        mfaCredentialRegistrationCallback?(.success(()))
    }
}
