import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

do {
    let updatedProfile = try await AppDelegate.reachfive().updatePhoneNumber(
        authToken: profileAuthToken,
        phoneNumber: "+33792244940"
    )
    // Get the updated profile
} catch {
    // Return a ReachFive error
}