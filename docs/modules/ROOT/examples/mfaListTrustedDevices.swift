import Reach5

Task {
    do {
        let trustedDevices = try await AppDelegate.reachfive().mfaListTrustedDevices(authToken: profileAuthToken)
        // Do something
    } catch {
        // Return a ReachFive error
    }
}