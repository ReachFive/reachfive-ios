import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

do {
    let updatedProfile = try await AppDelegate.reachfive().updateProfile(
        authToken: profileAuthToken,
        profile: Profile(givenName: "Jonathan", phoneNumber: "+33750253354")
    )
    // Get the updated profile
} catch {
    // Return a ReachFive error
}