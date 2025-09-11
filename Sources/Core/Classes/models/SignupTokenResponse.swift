import Foundation

public class SignupTokenResponse: Codable {
    public let idToken: String?
    public let accessToken: String?
    public let refreshToken: String?
    public let tokenType: String?
    public let expiresIn: Int?

    public init(idToken: String?, accessToken: String?, refreshToken: String?, tokenType: String? = nil, expiresIn: Int? = nil) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
    }
}
