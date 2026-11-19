import Foundation

/// The APNs environment a device token belongs to.
///
/// An app run from Xcode gets `sandbox` tokens; TestFlight and App Store builds get `production` ones.
/// The app cannot read it at runtime, so it is given by the integrator, typically from a build setting.
public enum ApnsEnvironment: String, Codable {
    case sandbox
    case production
}

/// A device registered to receive push notifications. The push token is never returned in full.
public class PushDevice: Codable {
    public let id: String
    public let platform: String
    public let maskedToken: String
    public let appVersion: String?
    public let enabled: Bool
    public let createdAt: String
    public let lastSeenAt: String

    public required init(id: String, platform: String, maskedToken: String, appVersion: String?, enabled: Bool, createdAt: String, lastSeenAt: String) {
        self.id = id
        self.platform = platform
        self.maskedToken = maskedToken
        self.appVersion = appVersion
        self.enabled = enabled
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

struct PushDeviceRegistrationRequest: DictionaryEncodable {
    let platform = "IOS"
    let pushToken: String
    let appVersion: String?
    let environment: ApnsEnvironment
    let topic: String
}

/// A CIBA request waiting for the user's decision on this device.
public class CibaRequest: Codable {
    public let authReqId: String
    public let clientId: String
    /// The name of the application that asks for the authentication, to show to the user
    public let clientName: String?
    public let scope: String
    /// The message shown on both devices, so the user can check they are approving the right request
    public let bindingMessage: String?
    public let createdAt: String
    public let expiresAt: String

    public required init(authReqId: String, clientId: String, clientName: String?, scope: String, bindingMessage: String?, createdAt: String, expiresAt: String) {
        self.authReqId = authReqId
        self.clientId = clientId
        self.clientName = clientName
        self.scope = scope
        self.bindingMessage = bindingMessage
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public enum CibaDecision: String, Codable {
    case approve
    case deny
}

struct CibaDecisionRequest: DictionaryEncodable {
    let authReqId: String
    let decision: CibaDecision
}
