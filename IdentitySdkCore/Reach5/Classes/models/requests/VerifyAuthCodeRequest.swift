import Foundation

public class VerifyAuthCodeRequest: Codable, DictionaryEncodable {
    let authType: PasswordLessAuthType?
    let phoneNumber: String?
    let email: String?
    let verificationCode: String
    let origin: String?
    
    public init(
        authType: PasswordLessAuthType? = nil,
        phoneNumber: String? = nil,
        email: String? = nil,
        verificationCode: String,
        origin: String? = nil
    ) {
        self.authType = authType
        self.phoneNumber = phoneNumber
        self.email = email
        self.verificationCode = verificationCode
        self.origin = origin
    }
}

public class VerifyPasswordlessRequest: Codable, DictionaryEncodable {
    let email: String?
    let phoneNumber: String?
    let verificationCode: String
    let state: String?
    let redirectUri: String?
    let clientId: String?
    let responseType: String?
    let origin: String?
    
    public init(
        email: String? = nil,
        phoneNumber: String? = nil,
        verificationCode: String,
        state: String? = nil,
        redirectUri: String? = nil,
        clientId: String? = nil,
        responseType: String? = nil,
        origin: String? = nil
    ) {
        self.email = email
        self.phoneNumber = phoneNumber
        self.verificationCode = verificationCode
        self.state = state
        self.redirectUri = redirectUri
        self.clientId = clientId
        self.responseType = responseType
        self.origin = origin
    }
}

public class PasswordlessVerifyResponse: Codable {
    let code: String?
    let state: String?
    
    public init(
        code: String?,
        state: String?
    ) {
        self.code = code
        self.state = state
    }
}
