import Reach5

Task {
    do {
        try await AppDelegate.reachfive().mfaDeleteCredential(
            phoneNumber: "+33682234940",
            authToken: profileAuthToken
        )
        // Do something
    } catch {
        // Return a ReachFive error
    }
}