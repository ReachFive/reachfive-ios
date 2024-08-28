import Alamofire
import BrightFutures
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

public enum StartStepUp{
    case StartStepUpAuthTokenFlow(redirectUri: String?, scope: [String]?, origin: String?, authType: MfaCredentialItemType, authToken: AuthToken)
    case StartStepUpLoginFlow(redirectUri: String?, origin: String?, authType: MfaCredentialItemType, stepUpToken: String)
}

public class ContinueStepUp {
    public let challengeId: String
    public let reachfive: ReachFive

    fileprivate init(challengeId: String, reachFive: ReachFive) {
        self.challengeId = challengeId
        self.reachfive = reachFive
    }
    
    public func verify(code: String, trustDevice: Bool? = nil) -> Future<AuthToken, ReachFiveError> {
        reachfive.mfaVerify(stepUp: VerifyStepUp(challengeId: challengeId, verificationCode: code, trustDevice: trustDevice))
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
    
    public func verify(code: String, freshAuthToken: AuthToken? = nil) -> Future<MfaCredentialItem, ReachFiveError> {
        reachfive.mfaVerify(credentialType, code: code, authToken: freshAuthToken ?? authToken)
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
    
    func mfaStart(registering credential: Credential, authToken: AuthToken) -> Future<MfaStartRegistrationResponse, ReachFiveError> {
        let registration =
            switch credential {
            case let .Email(redirectUrl):
                reachFiveApi.startMfaEmailRegistration(MfaStartEmailRegistrationRequest(redirectUrl: redirectUrl ?? sdkConfig.mfaUri), authToken: authToken)
            case let .PhoneNumber(phoneNumber):
                reachFiveApi.startMfaPhoneRegistration(MfaStartPhoneRegistrationRequest(phoneNumber: phoneNumber), authToken: authToken)
            }
        
        return registration.map { resp in
            switch resp.status {
            case "enabled": .Success(resp.credential!)
            default: .VerificationNeeded(ContinueRegistration(credentialType: credential.credentialType, reachfive: self, authToken: authToken))
            }
        }
    }
    
    func mfaVerify(_ credentialType: CredentialType, code: String, authToken: AuthToken) -> Future<MfaCredentialItem, ReachFiveError> {
        switch credentialType {
        case .Email:
            let request = MfaVerifyEmailRegistrationPostRequest(code)
            return reachFiveApi.verifyMfaEmailRegistrationPost(request, authToken: authToken)
        case .PhoneNumber:
            let request = MfaVerifyPhoneRegistrationRequest(code)
            return reachFiveApi.verifyMfaPhoneRegistration(request, authToken: authToken)
        }
    }
    
    func mfaListCredentials(authToken: AuthToken) -> Future<MfaCredentialsListResponse, ReachFiveError> {
        return reachFiveApi.mfaListCredentials(authToken: authToken)
    }
    
    func mfaStart(stepUp request: StartStepUp) -> Future<ContinueStepUp, ReachFiveError> {
        switch request {
        case .StartStepUpLoginFlow(let redirectUri, let origin, let authType, let stepUpToken):
            return self.reachFiveApi.startPasswordless(mfa: StartMfaPasswordlessRequest(redirectUri: redirectUri ?? sdkConfig.redirectUri, clientId: self.sdkConfig.clientId, stepUp: stepUpToken, authType: authType, origin: origin))
                .map { response in
                    ContinueStepUp(challengeId: response.challengeId, reachFive: self)
                }
        case .StartStepUpAuthTokenFlow(let redirectUri, let overwrittenScope, let origin, let authType, let authToken):
            let pkce = Pkce.generate()
            storage.save(key: pkceKey, value: pkce)
            return reachFiveApi.startMfaStepUp(StartMfaStepUpRequest(clientId: sdkConfig.clientId,
                                                                     redirectUri: redirectUri ?? sdkConfig.redirectUri,
                                                                     codeChallenge: pkce.codeChallenge,
                                                                     codeChallengeMethod: pkce.codeChallengeMethod,
                                                                     scope: (overwrittenScope ?? scope).joined(separator: " "),
                                                                     tkn: nil,
                                                                     stepUp: nil),
                                               authToken: authToken).flatMap { result in
                self.reachFiveApi.startPasswordless(mfa: StartMfaPasswordlessRequest(redirectUri: redirectUri ?? self.sdkConfig.redirectUri, clientId: self.sdkConfig.clientId, stepUp: result.token, authType: authType, origin: origin))
            }.map { response in
                ContinueStepUp(challengeId: response.challengeId, reachFive: self)
            }
        }
    }
    
    func mfaVerify(stepUp request: VerifyStepUp) -> Future<AuthToken, ReachFiveError> {
        let pkce: Pkce? = storage.take(key: pkceKey)
        guard let pkce else {
            return Future(error: .TechnicalError(reason: "Pkce not found"))
        }
        return reachFiveApi
            .verifyPasswordless(mfa: VerifyMfaPasswordlessRequest(challengeId: request.challengeId, verificationCode: request.verificationCode, trustDevice: request.trustDevice))
            .flatMap { response in
                guard let code = response.code else {
                    return Future(error: .TechnicalError(reason: "No authorization code"))
                }
                return self.authWithCode(code: code, pkce: pkce)
            }
    }
    
    func mfaDeleteCredential(_ phoneNumber: String? = nil, authToken: AuthToken) -> Future<Void, ReachFiveError> {
        guard let phoneNumber else {
            return reachFiveApi.deleteMfaEmailCredential(authToken: authToken)
        }
        return reachFiveApi
            .deleteMfaPhoneNumberCredential(phoneNumber: phoneNumber, authToken: authToken)
    }
    
    func mfaListTrustedDevices(authToken: AuthToken) -> Future<[TrustedDevice], ReachFiveError> {
        return reachFiveApi
            .listMfaTrustedDevices(authToken: authToken)
            .map{ res in res.trustedDevices }
    }
    
    func mfaDelete(trustedDeviceId deviceId: String, authToken: AuthToken) -> Future<Void, ReachFiveError> {
        return reachFiveApi.deleteMfaTrustedDevice(deviceId: deviceId, authToken: authToken)
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
