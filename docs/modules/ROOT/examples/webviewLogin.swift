do {
    let authToken = try await AppDelegate.reachfive().webviewLogin(WebviewLoginRequest(
        state: "zf3ifjfmdkj",
        nonce: "n-0S6_PzA3Ze",
        scope: ["openid", "profile", "email"],
        presentationContextProvider: self
    ))
    // Get the profile's authentication token
} catch {
    // Return a ReachFive error
}