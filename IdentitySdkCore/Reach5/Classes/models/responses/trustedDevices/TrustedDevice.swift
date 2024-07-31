import Foundation

public struct MfaListTrustedDevices: Codable, DictionaryEncodable {
    public let trustedDevices: [TrustedDevice]
}

public class TrustedDevice: Codable, DictionaryEncodable {
    public let id: String
    public let userId: String
    public let createdAt: String
    public let metadata: DeviceMetadata
    
    public init(id: String, userId: String, createdAt: String, metadata: DeviceMetadata) {
        self.id = id
        self.userId = userId
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

extension TrustedDevice: Hashable, Equatable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: TrustedDevice, rhs: TrustedDevice) -> Bool {
        return lhs.id == rhs.id
    }
}

public class DeviceMetadata: Codable, DictionaryEncodable{
    public let ip: String?
    public let operatingSystem: String?
    public let userAgent: String?
    public let deviceClass: String?
    public let deviceName: String?
    
    public init(ip: String?, operatingSystem: String?, userAgent: String?, deviceClass: String?, deviceName: String?) {
        self.ip = ip
        self.operatingSystem = operatingSystem
        self.userAgent = userAgent
        self.deviceClass = deviceClass
        self.deviceName = deviceName
    }
}
