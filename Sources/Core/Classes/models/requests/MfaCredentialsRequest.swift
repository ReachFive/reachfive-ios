import Foundation

public class MfaStartEmailRegistrationRequest: Codable, DictionaryEncodable {
    public let redirectUrl: String?

    public init(redirectUrl: String? = nil) {
        self.redirectUrl = redirectUrl
    }
}

public class MfaStartPhoneRegistrationRequest: Codable, DictionaryEncodable {
    public let phoneNumber: String

    public init(phoneNumber: String) {
        self.phoneNumber = phoneNumber
    }
}

public class MfaVerifyEmailRegistrationPostRequest: Codable, DictionaryEncodable {
    public let verificationCode: String

    public init(_ verificationCode: String) {
        self.verificationCode = verificationCode
    }
}

public class MfaVerifyEmailRegistrationGetRequest: Codable, DictionaryEncodable {
    public let c: String
    public let t: String

    public init(c: String, t: String) {
        self.c = c
        self.t = t
    }
}

public class MfaVerifyPhoneRegistrationRequest: Codable, DictionaryEncodable {
    public let verificationCode: String

    public init(_ verificationCode: String) {
        self.verificationCode = verificationCode
    }
}

public class MfaStartCredentialRegistrationResponse: Codable, DictionaryEncodable {
    public let status: String
    public let credential: MfaCredentialItem?

    public init(status: String, credential: MfaCredentialItem? = nil) {
        self.status = status
        self.credential = credential
    }
}

public enum Status: String {
    case emailSent = "email_sent"
    case enabled
    case smsSent = "sms_sent"
}

public enum MfaCredentialItemType: String, Codable {
    case email
    case sms
}

public class MfaCredentialItem: Codable, DictionaryEncodable {
    public let createdAt: String
    public let friendlyName: String
    public let phoneNumber: String?
    public let email: String?
    public let type: MfaCredentialItemType

    public init(createdAt: String, friendlyName: String, type: MfaCredentialItemType, phoneNumber: String? = nil, email: String? = nil) {
        self.createdAt = createdAt
        self.friendlyName = friendlyName
        self.phoneNumber = phoneNumber
        self.email = email
        self.type = type
    }
}

public class MfaCredentialsListResponse: Codable, DictionaryEncodable {
    public let credentials: [MfaCredentialItem]

    public init(credentials: [MfaCredentialItem]) {
        self.credentials = credentials
    }
}
