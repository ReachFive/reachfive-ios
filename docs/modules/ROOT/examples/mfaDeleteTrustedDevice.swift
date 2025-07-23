import Reach5

Task {
    do {
        try await AppDelegate.reachfive().mfaDelete(trustedDeviceId: deviceId, authToken: profileAuthToken)
        // Do something
    } catch {
        // Return a ReachFive error
    }
}