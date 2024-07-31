import Foundation

public class ProfileAddress: Codable, DictionaryEncodable {
    public let title: String?
    public let isDefault: Bool?
    public let addressType: String?
    public let streetAddress: String?
    public let addressComplement: String?
    public let locality: String?
    public let region: String?
    public let postalCode: String?
    public let country: String?
    public let raw: String?
    public let deliveryNote: String?
    public let recipient: String?
    public let company: String?
    public let phoneNumber: String?
    public let customFields: [String: CustomField]?
    
    private enum CodingKeys: String, CodingKey {
        case title
        case isDefault = "default"
        case addressType
        case streetAddress
        case addressComplement
        case locality
        case region
        case postalCode
        case country
        case raw
        case deliveryNote
        case recipient
        case company
        case phoneNumber
        case customFields
    }
    
    public init(
        title: String?,
        isDefault: Bool?,
        addressType: String?,
        streetAddress: String?,
        addressComplement: String?,
        locality: String?,
        region: String?,
        postalCode: String?,
        country: String?,
        raw: String?,
        deliveryNote: String?,
        recipient: String?,
        company: String?,
        phoneNumber: String?,
        customFields: [String: CustomField]?
    ) {
        self.title = title
        self.isDefault = isDefault
        self.addressType = addressType
        self.streetAddress = streetAddress
        self.addressComplement = addressComplement
        self.locality = locality
        self.region = region
        self.postalCode = postalCode
        self.country = country
        self.raw = raw
        self.deliveryNote = deliveryNote
        self.recipient = recipient
        self.company = company
        self.phoneNumber = phoneNumber
        self.customFields = customFields
    }
}
