import Foundation
import BrightFutures

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
    
    public static func fromOpenIdTokenResponseFuture(
        _ openIdTokenResponse: AccessTokenResponse
    ) -> Future<AuthToken, ReachFiveError> {
        Future(result: AuthToken.fromOpenIdTokenResponse(openIdTokenResponse: openIdTokenResponse))
    }
    
    static func fromOpenIdTokenResponse(openIdTokenResponse: AccessTokenResponse) -> Result<AuthToken, ReachFiveError> {
        if let token = openIdTokenResponse.idToken {
            return fromIdToken(token).flatMap { user in
                .success(withUser(openIdTokenResponse, user))
            }
        } else {
            return .success(withUser(openIdTokenResponse, nil))
        }
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
    
    static func fromIdToken(_ idToken: String) -> Result<OpenIdUser, ReachFiveError> {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let parts = idToken.components(separatedBy: ".")
        if parts.count == 3 {
            let data = parts[1].decodeBase64Url()
            let user = Result.init(catching: {
                try decoder.decode(OpenIdUser.CodingData.self, from: data!).openIdUser
            })
            return user.mapError({ error in
                .TechnicalError(reason: error.localizedDescription)
            })
        } else {
            return .failure(.TechnicalError(reason: "idToken invalid"))
        }
    }
}
