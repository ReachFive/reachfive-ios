import Reach5

do {
    try await AppDelegate.reachfive().mfaDeleteCredential(authToken: profileAuthToken)
    // Do something
} catch {
    // Return a ReachFive error
}