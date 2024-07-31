import Foundation

public enum PasswordLessAuthType: String, Codable {
    case MagicLink = "magic_link"
    case SMS = "sms"
}

public class StartPasswordlessRequest: Codable, DictionaryEncodable {
    public let clientId: String
    public let email: String?
    public let phoneNumber: String?
    public let responseType: String
    public let authType: String
    public let redirectUri: String
    public let state: String?
    public let codeChallenge: String
    public let codeChallengeMethod: String
    public let origin: String?

    public convenience init(
        clientId: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        authType: PasswordLessAuthType,
        redirectUri: String,
        codeChallenge: String,
        codeChallengeMethod: String,
        origin: String? = nil
    ) {
        self.init(
            clientId: clientId,
            email: email,
            phoneNumber: phoneNumber,
            responseType: "code",
            authType: authType,
            redirectUri: redirectUri,
            state: "passwordless",
            codeChallenge: codeChallenge,
            codeChallengeMethod: codeChallengeMethod,
            origin: origin
        )
    }

    public init(
        clientId: String,
        email: String?,
        phoneNumber: String?,
        responseType: String,
        authType: PasswordLessAuthType,
        redirectUri: String,
        state: String? = nil,
        codeChallenge: String,
        codeChallengeMethod: String,
        origin: String? = nil
    ) {
        self.clientId = clientId
        self.email = email
        self.phoneNumber = phoneNumber
        self.responseType = responseType
        self.authType = authType.rawValue
        self.redirectUri = redirectUri
        self.state = state
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
        self.origin = origin
    }
}
