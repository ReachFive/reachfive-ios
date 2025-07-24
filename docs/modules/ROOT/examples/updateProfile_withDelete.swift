import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

do {
    let updatedProfile = try await AppDelegate.reachfive().updateProfile(
        authToken: profileAuthToken,
        profileUpdate: ProfileUpdate(phoneNumber: .Delete)
    )
    // Get the updated profile
} catch {
    // Return a ReachFive error
}