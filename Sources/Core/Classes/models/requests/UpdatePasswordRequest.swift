import Foundation

public enum UpdatePasswordParams {
    case FreshAccessTokenParams(authToken: AuthToken, password: String)
    case AccessTokenParams(authToken: AuthToken, password: String, oldPassword: String)
    case EmailParams(email: String, verificationCode: String, password: String)
    case SmsParams(phoneNumber: String, verificationCode: String, password: String)

    public func getAuthToken() -> AuthToken? {
        switch self {
        case let .FreshAccessTokenParams(authToken, _):
            authToken
        case let .AccessTokenParams(authToken, _, _):
            authToken
        default:
            nil
        }
    }
}

public class UpdatePasswordRequest: Codable, DictionaryEncodable {
    let clientId: String?
    let password: String?
    let oldPassword: String?
    let email: String?
    let phoneNumber: String?
    let verificationCode: String?

    public init(
        clientId: String? = nil,
        password: String? = nil,
        oldPassword: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        verificationCode: String? = nil
    ) {
        self.clientId = clientId
        self.password = password
        self.oldPassword = oldPassword
        self.email = email
        self.phoneNumber = phoneNumber
        self.verificationCode = verificationCode
    }

    public convenience init(updatePasswordParams: UpdatePasswordParams, sdkConfig: SdkConfig) {
        switch updatePasswordParams {
        case let .FreshAccessTokenParams(_, password):
            self.init(password: password)
        case let .AccessTokenParams(_, password, oldPassword):
            self.init(password: password, oldPassword: oldPassword)
        case let .EmailParams(email, verificationCode, password):
            self.init(clientId: sdkConfig.clientId, password: password, email: email, verificationCode: verificationCode)
        case let .SmsParams(phoneNumber, verificationCode, password):
            self.init(clientId: sdkConfig.clientId, password: password, phoneNumber: phoneNumber, verificationCode: verificationCode)
        }
    }
}
