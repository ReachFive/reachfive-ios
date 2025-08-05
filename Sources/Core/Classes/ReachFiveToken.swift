import Foundation

public extension ReachFive {
    func refreshAccessToken(authToken: AuthToken) async throws -> AuthToken {
        let refreshRequest = RefreshRequest(
            clientId: sdkConfig.clientId,
            refreshToken: authToken.refreshToken,
            redirectUri: sdkConfig.scheme
        )
        let token = try await reachFiveApi.refreshAccessToken(refreshRequest)
        return try AuthToken.fromOpenIdTokenResponse(token)
    }


    /// Revokes a token.
    ///
    /// This method allows you to invalidate a token (either an access token or a refresh token).
    /// The token is sent to the ReachFive `/oauth/revoke` endpoint for invalidation.
    ///
    /// - Parameters:
    ///   - authToken: The `AuthToken` containing the tokens.
    ///   - tokenTypeHint: A hint to the server about the type of token being sent.
    ///
    /// - Throws: A `ReachFiveError` if the request fails.
    func revokeToken(
        authToken: AuthToken,
        tokenType: TokenType
    ) async throws {
        let token: String
        switch tokenType {
        case .accessToken:
            token = authToken.accessToken
        case .refreshToken:
            guard let refreshToken = authToken.refreshToken else {
                throw ReachFiveError.TechnicalError(reason: "No refresh token found in AuthToken")
            }
            token = refreshToken
        }
        
        let revokeTokenRequest = RevokeTokenRequest(
            token: token,
            tokenTypeHint: tokenType.rawValue,
            clientId: sdkConfig.clientId
        )
        return try await reachFiveApi.revokeToken(revokeTokenRequest: revokeTokenRequest)
    }
}
