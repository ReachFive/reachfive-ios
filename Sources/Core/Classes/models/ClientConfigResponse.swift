import Foundation

public class ClientConfigResponse: Codable {
    public let scope: String
    public let sms: Bool
    
    public init(scope: String, sms: Bool) {
        self.scope = scope
        self.sms = sms
    }
}
