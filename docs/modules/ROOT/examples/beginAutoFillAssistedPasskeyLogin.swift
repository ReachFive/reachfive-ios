do {
    let authToken = try await AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(anchor: window))
    // get auth token on success
} catch {
    // return ReachFive error on failure
}