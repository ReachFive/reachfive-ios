import Foundation

public class AccessTokenResponse: Codable {
    public let idToken: String?
    public let accessToken: String
    public let refreshToken: String?
    public let code: String?
    public let tokenType: String?
    public let expiresIn: Int?
    public let error: String?
    public let errorDescription: String?
    
    public init(idToken: String?, accessToken: String, refreshToken: String?, code: String?, tokenType: String?, expiresIn: Int?, error: String?, errorDescription: String?) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.code = code
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.error = error
        self.errorDescription = errorDescription
    }
}
