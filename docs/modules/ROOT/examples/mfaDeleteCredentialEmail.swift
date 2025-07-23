import Reach5

Task {
    do {
        try await AppDelegate.reachfive().mfaDeleteCredential(authToken: profileAuthToken)
        // Do something
    } catch {
        // Return a ReachFive error
    }
}