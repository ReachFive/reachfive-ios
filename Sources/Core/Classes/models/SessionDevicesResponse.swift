import Foundation


public class ListSessionDevices: Codable {
    public let sessionDevices: [SessionDevice]
    
    public required init(sessionDevices: [SessionDevice]) {
        self.sessionDevices = sessionDevices
    }
}

public enum SessionDeviceTokenType: String, Codable {
    case rt = "RT"
    case st = "ST"
}

public class SessionDevice: Codable {
    public let id: String
    public let tokenType: SessionDeviceTokenType
    public let ip: String
    public let country: String?
    public let city: String?
    public let operatingSystem: String?
    public let userAgentName: String?
    public let deviceClass: String?
    public let deviceName: String?
    public let createdAt: String
    public let lastConnection: String
    public let expiresAt: String
    
    public required init(
        id: String,
        tokenType: SessionDeviceTokenType,
        ip: String,
        country: String? = nil,
        city: String? = nil,
        operatingSystem: String? = nil,
        userAgentName: String? = nil,
        deviceClass: String? = nil,
        deviceName: String? = nil,
        createdAt: String,
        lastConnection: String,
        expiresAt: String
    ) {
        self.id = id
        self.tokenType = tokenType
        self.ip = ip
        self.country = country
        self.city = city
        self.operatingSystem = operatingSystem
        self.userAgentName = userAgentName
        self.deviceClass = deviceClass
        self.deviceName = deviceName
        self.createdAt = createdAt
        self.lastConnection = lastConnection
        self.expiresAt = expiresAt
    }
}
