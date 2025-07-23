import Foundation

public class AuthToken: Codable {
    public let idToken: String?
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String?
    public let expiresIn: Int?
    public let user: OpenIdUser?

    public init(
        idToken: String?,
        accessToken: String,
        refreshToken: String?,
        tokenType: String?,
        expiresIn: Int?,
        user: OpenIdUser?
    ) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.user = user
    }

    public static func fromOpenIdTokenResponse(_ openIdTokenResponse: AccessTokenResponse) throws -> AuthToken {
        guard let token = openIdTokenResponse.idToken else {
            return withUser(openIdTokenResponse, nil)
        }
        
        let user = try fromIdToken(token)
        return withUser(openIdTokenResponse, user)
    }

    static func withUser(_ accessTokenResponse: AccessTokenResponse, _ user: OpenIdUser?) -> AuthToken {
        AuthToken(
            idToken: accessTokenResponse.idToken,
            accessToken: accessTokenResponse.accessToken,
            refreshToken: accessTokenResponse.refreshToken,
            tokenType: accessTokenResponse.tokenType,
            expiresIn: accessTokenResponse.expiresIn,
            user: user
        )
    }

    static func fromIdToken(_ idToken: String) throws -> OpenIdUser {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let parts = idToken.components(separatedBy: ".")
        guard
            parts.count == 3,
            let data = parts[1].decodeBase64Url()
        else {
            throw ReachFiveError.TechnicalError(reason: "idToken invalid")
        }
        
        do {
            return try decoder.decode(OpenIdUser.CodingData.self, from: data).openIdUser
        } catch {
            throw ReachFiveError.TechnicalError(reason: error.localizedDescription)
        }
    }
}
