import Foundation

public class StartMfaStepUpRequest: Codable, DictionaryEncodable {
    public let responseType: String
    public let clientId: String
    public let redirectUri: String
    public let codeChallenge: String
    public let codeChallengeMethod: String
    public let scope: String?
    public let tkn: String?

    public init(clientId: String, redirectUri: String, pkce: Pkce, scope: String? = nil, tkn: String? = nil) {
        self.clientId = clientId
        self.responseType = "code"
        self.redirectUri = redirectUri
        self.codeChallenge = pkce.codeChallenge
        self.codeChallengeMethod = pkce.codeChallengeMethod
        self.scope = scope
        self.tkn = tkn
    }
}

public class StartMfaStepUpResponse: Codable, DictionaryEncodable {
    public let amr: [MfaCredentialItemType]
    public let token: String

    public init(amr: [MfaCredentialItemType], token: String) {
        self.amr = amr
        self.token = token
    }
}

public class StartMfaPasswordlessRequest: Codable, DictionaryEncodable {
    public let responseType: String
    public let redirectUri: String
    public let clientId: String
    public let stepUp: String
    public let authType: MfaCredentialItemType
    public let origin: String?

    public init(redirectUri: String, clientId: String, stepUp: String, authType: MfaCredentialItemType, origin: String?) {
        self.redirectUri = redirectUri
        self.responseType = "code"
        self.clientId = clientId
        self.stepUp = stepUp
        self.authType = authType
        self.origin = origin
    }
}

public class StartMfaPasswordlessResponse: Codable, DictionaryEncodable {
    public let challengeId: String

    public init(challengeId: String) {
        self.challengeId = challengeId
    }
}

public class VerifyMfaPasswordlessRequest: Codable, DictionaryEncodable {
    public let challengeId: String
    public let verificationCode: String
    public let trustDevice: Bool?

    public init(challengeId: String, verificationCode: String, trustDevice: Bool? = nil) {
        self.challengeId = challengeId
        self.verificationCode = verificationCode
        self.trustDevice = trustDevice
    }
}
