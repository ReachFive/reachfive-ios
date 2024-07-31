import Foundation

public class AuthCodeRequest: Codable, DictionaryEncodable {
    public let clientId: String
    public let code: String
    public let grantType: String
    public let redirectUri: String
    public let codeVerifier: String
    
    public convenience init(
        clientId: String,
        code: String,
        redirectUri: String,
        pkce: Pkce
    ) {
        self.init(
            clientId: clientId,
            code: code,
            grantType: "authorization_code",
            redirectUri: redirectUri,
            codeVerifier: pkce.codeVerifier
        )
    }
    
    public init(
        clientId: String,
        code: String,
        grantType: String,
        redirectUri: String,
        codeVerifier: String
    ) {
        self.clientId = clientId
        self.code = code
        self.grantType = grantType
        self.redirectUri = redirectUri
        self.codeVerifier = codeVerifier
    }
}
