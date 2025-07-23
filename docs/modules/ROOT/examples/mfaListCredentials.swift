import Reach5

do {
    let credentials = try await AppDelegate.reachfive().mfaListCredentials(authToken: profileAuthToken)
    // Do something
} catch {
    // Return a ReachFive error
}