import Reach5

do {
    let signupFlow = try await AppDelegate.reachfive().signup(
        profile: ProfileSignupRequest(
            password: "hjk90wxc",
            phoneNumber: "+353875551234",
            customIdentifier: "coolCat55",
            givenName: "John",
            familyName: "Doe",
            gender: "male"
        ),
        scope: ["openid", "profile", "phone"]
    )

    switch signupFlow {
    case .AchievedLogin(authToken: let authToken):
        // Signup completed and user is logged in
        // Use authToken as needed
    case .AwaitingIdentifierVerification:
        // Signup completed but phone verification is required
    }
} catch {
    // Handle ReachFive error
}
