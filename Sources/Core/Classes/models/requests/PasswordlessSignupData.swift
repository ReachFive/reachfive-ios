import Foundation

/// The profile a passwordless start creates if it resolves to a signup, written once the code is verified.
/// Ignored when the identifier already has a profile, and unless the account accepts profile data in its
/// passwordless settings (off by default).
///
/// The identifier of the flow stays in `PasswordLessRequest`. An `email` or `phoneNumber` here of the same kind
/// is ignored; one of the other kind is written to the profile unverified.
public class PasswordlessSignupData: Codable, DictionaryEncodable {
    public let email: String?
    public let phoneNumber: String?
    public let givenName: String?
    public let middleName: String?
    public let familyName: String?
    public let name: String?
    public let nickname: String?
    public let username: String?
    public let birthdate: String?
    public let gender: String?
    public let addresses: [ProfileAddress]?
    public let picture: String?
    public let company: String?
    public let locale: String?
    public let customFields: [String: CustomField]?
    public let consents: [String: Consent]?

    public init(
        email: String? = nil,
        phoneNumber: String? = nil,
        givenName: String? = nil,
        middleName: String? = nil,
        familyName: String? = nil,
        name: String? = nil,
        nickname: String? = nil,
        username: String? = nil,
        birthdate: String? = nil,
        gender: String? = nil,
        addresses: [ProfileAddress]? = nil,
        picture: String? = nil,
        company: String? = nil,
        locale: String? = nil,
        customFields: [String: CustomField]? = nil,
        consents: [String: Consent]? = nil
    ) {
        self.email = email
        self.phoneNumber = phoneNumber
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.name = name
        self.nickname = nickname
        self.username = username
        self.birthdate = birthdate
        self.gender = gender
        self.addresses = addresses
        self.picture = picture
        self.company = company
        self.locale = locale
        self.customFields = customFields
        self.consents = consents
    }
}
