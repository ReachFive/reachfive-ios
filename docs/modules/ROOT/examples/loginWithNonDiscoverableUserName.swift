Task {
    do {
        let authToken = try await AppDelegate.reachfive().login(
            withNonDiscoverableUsername: .Unspecified(username),
            forRequest: NativeLoginRequest(anchor: window),
            usingModalAuthorizationFor: [.Passkey],
            display: .Always
        )
        // get auth token on success
    } catch {
        // return ReachFive error on failure
    }
}