import Foundation

public class ProfileSignupRequest: Codable, DictionaryEncodable {
    public let password: String
    public let email: String?
    public let phoneNumber: String?
    public let customIdentifier: String?
    public let givenName: String?
    public let middleName: String?
    public let familyName: String?
    public let name: String?
    public let nickname: String?
    public let birthdate: String?
    public let profileURL: String?
    public let picture: String?
    public let username: String?
    public let gender: String?
    public let addresses: [ProfileAddress]?
    public let locale: String?
    public let bio: String?
    public let customFields: [String: CustomField]?
    public let consents: [String: Consent]?
    public let company: String?
    public let liteOnly: Bool?
    
    public required init(
        password: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        customIdentifier: String? = nil,
        givenName: String? = nil,
        middleName: String? = nil,
        familyName: String? = nil,
        name: String? = nil,
        nickname: String? = nil,
        birthdate: String? = nil,
        profileURL: String? = nil,
        picture: String? = nil,
        username: String? = nil,
        gender: String? = nil,
        addresses: [ProfileAddress]? = nil,
        locale: String? = nil,
        bio: String? = nil,
        customFields: [String: CustomField]? = nil,
        consents: [String: Consent]? = nil,
        company: String? = nil,
        liteOnly: Bool? = nil
    ) {
        self.password = password
        self.email = email
        self.phoneNumber = phoneNumber
        self.customIdentifier = customIdentifier
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.name = name
        self.nickname = nickname
        self.birthdate = birthdate
        self.profileURL = profileURL
        self.picture = picture
        self.username = username
        self.gender = gender
        self.addresses = addresses
        self.locale = locale
        self.bio = bio
        self.customFields = customFields
        self.consents = consents
        self.company = company
        self.liteOnly = liteOnly
    }
}
