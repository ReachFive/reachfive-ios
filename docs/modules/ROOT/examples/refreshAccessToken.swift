import Reach5

let authToken: AuthToken = // The authentication token obtained from login or signup.

Task {
    do {
        let refreshedAuthToken = try await AppDelegate.reachfive().refreshAccessToken(authToken)
        // Do something
    } catch {
        // Return a ReachFive error
    }
}