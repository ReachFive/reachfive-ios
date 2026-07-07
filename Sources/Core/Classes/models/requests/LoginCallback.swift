import Foundation

public class LoginCallback: Codable, DictionaryEncodable {
    public let clientId: String
    public let responseType: String
    public let redirectUri: URL
    public let scope: String
    public let codeChallenge: String
    public let codeChallengeMethod: String
    public let tkn: String?
    public let origin: String?

    public init(sdkConfig: SdkConfig, scope: String, pkce: Pkce, tkn: String? = nil, origin: String? = nil) {
        clientId = sdkConfig.clientId
        redirectUri = sdkConfig.redirectUri
        codeChallenge = pkce.codeChallenge
        codeChallengeMethod = pkce.codeChallengeMethod
        responseType = "code"
        self.tkn = tkn
        self.scope = scope
        self.origin = origin
    }
}
