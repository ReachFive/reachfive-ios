import Foundation

public class Profile: Codable, DictionaryEncodable {
    public let uid: String?
    public let givenName: String?
    public let middleName: String?
    public let familyName: String?
    public let name: String?
    public let nickname: String?
    public let birthdate: String?
    public let profileURL: String?
    public let picture: String?
    public let externalId: String?
    public let authTypes: [String]?
    public let loginSummary: LoginSummary?
    public let username: String?
    public let gender: String?
    public let email: String?
    public let emailVerified: Bool?
    public let emails: Emails?
    public let phoneNumber: String?
    public let phoneNumberVerified: Bool?
    public let customIdentifier: String?
    public let addresses: [ProfileAddress]?
    public let locale: String?
    public let bio: String?
    public let customFields: [String: CustomField]?
    public let consents: [String: Consent]?
    public let createdAt: String?
    public let updatedAt: String?
    public let company: String?
    public let liteOnly: Bool?
    
    public required init(
        uid: String? = nil,
        givenName: String? = nil,
        middleName: String? = nil,
        familyName: String? = nil,
        name: String? = nil,
        nickname: String? = nil,
        birthdate: String? = nil,
        profileURL: String? = nil,
        picture: String? = nil,
        externalId: String? = nil,
        authTypes: [String]? = nil,
        loginSummary: LoginSummary? = nil,
        username: String? = nil,
        gender: String? = nil,
        email: String? = nil,
        emailVerified: Bool? = nil,
        emails: Emails? = nil,
        phoneNumber: String? = nil,
        phoneNumberVerified: Bool? = nil,
        customIdentifier: String? = nil,
        addresses: [ProfileAddress]? = nil,
        locale: String? = nil,
        bio: String? = nil,
        customFields: [String: CustomField]? = nil,
        consents: [String: Consent]? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        company: String? = nil,
        liteOnly: Bool? = nil
    ) {
        self.uid = uid
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.name = name
        self.nickname = nickname
        self.birthdate = birthdate
        self.profileURL = profileURL
        self.picture = picture
        self.externalId = externalId
        self.authTypes = authTypes
        self.loginSummary = loginSummary
        self.username = username
        self.gender = gender
        self.email = email
        self.emailVerified = emailVerified
        self.emails = emails
        self.phoneNumber = phoneNumber
        self.phoneNumberVerified = phoneNumberVerified
        self.customIdentifier = customIdentifier
        self.addresses = addresses
        self.locale = locale
        self.bio = bio
        self.customFields = customFields
        self.consents = consents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.company = company
        self.liteOnly = liteOnly
    }
}
