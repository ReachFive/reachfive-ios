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

    /// Revokes the tokens.
    ///
    /// This method allows you to invalidate the access and refresh tokens.
    func revokeToken(authToken: AuthToken) async throws {
        let revokeAccessToken = RevokeTokenRequest(
            token: authToken.accessToken,
            tokenTypeHint: TokenType.accessToken.rawValue,
            clientId: sdkConfig.clientId
        )
        try await reachFiveApi.revokeToken(revokeTokenRequest: revokeAccessToken)
        
        if let refreshToken = authToken.refreshToken {
            let revokeRefreshToken = RevokeTokenRequest(
                token: refreshToken,
                tokenTypeHint: TokenType.refreshToken.rawValue,
                clientId: sdkConfig.clientId
            )
            try await reachFiveApi.revokeToken(revokeTokenRequest: revokeRefreshToken)
        }
    }
}
