Task {
    do {
        try await AppDelegate.reachfive().registerNewPasskey(withRequest: NewPasskeyRequest(anchor: window, friendlyName: friendlyName), authToken: authToken)
        // get auth token on success
    } catch {
        // return ReachFive error on failure
    }
}