do {
    try await AppDelegate.reachfive().registerNewPasskey(withRequest: NewPasskeyRequest(presenting: presenting, friendlyName: friendlyName), authToken: authToken)
    // get auth token on success
} catch {
    // return ReachFive error on failure
}