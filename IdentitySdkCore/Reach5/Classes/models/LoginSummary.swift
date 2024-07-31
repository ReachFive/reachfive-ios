import Foundation

public class LoginSummary: Codable, DictionaryEncodable {
    public let firstLogin: Int?
    public let lastLogin: Int?
    public let total: Int?
    public let origins: [String]?
    public let devices: [String]?
    public let lastProvider: String?
    
    public init(
        firstLogin: Int?,
        lastLogin: Int?,
        total: Int?,
        origins: [String]?,
        devices: [String]?,
        lastProvider: String?
    ) {
        self.firstLogin = firstLogin
        self.lastLogin = lastLogin
        self.total = total
        self.origins = origins
        self.devices = devices
        self.lastProvider = lastProvider
    }
}
