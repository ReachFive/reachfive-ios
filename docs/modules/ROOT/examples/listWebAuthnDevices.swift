import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

Task {
    do {
        let listDevices = try await AppDelegate.reachfive().listWebAuthnDevices(authToken: profileAuthToken)
        // Get the list of devices
    } catch {
        // Return a ReachFive error
    }
}
