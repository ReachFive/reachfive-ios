do {
    let authToken = try await AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(presenting: presenting))
    // get auth token on success
} catch {
    // return ReachFive error on failure
}