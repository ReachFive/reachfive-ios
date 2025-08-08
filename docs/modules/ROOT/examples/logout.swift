// Basic logout (no parameters)
do {
    try await AppDelegate.reachfive().logout()
    // User is logged out from provider sessions and main SSO session
    // Tokens are not revoked, and browser cookies are not cleared
} catch {
    // Handle ReachFiveError
}

// Native logout with token revocation
do {
    let authToken = // Obtain AuthToken from storage or authentication
    try await AppDelegate.reachfive().logout(revoke: authToken)
    // User is logged out, tokens are revoked
} catch {
    // Handle ReachFiveError
}

// Web-based logout with redirect
do {
    let WebSessionLogoutRequest = WebSessionLogoutRequest(
        origin: "app_logout",
        presentationContextProvider: // Provide a context provider, e.g., a view controller
    )
    try await AppDelegate.reachfive().logout(webSessionLogout: WebSessionLogoutRequest)
    // Browser cookies are cleared, user is redirected
} catch {
    // Handle ReachFiveError
}