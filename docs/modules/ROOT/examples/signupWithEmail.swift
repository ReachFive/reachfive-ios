import Reach5

do {
    let signupFlow = try await AppDelegate.reachfive().signup(
        profile: ProfileSignupRequest(
            password: "hjk90wxc",
            email: "john.doe@gmail.com",
            customIdentifier: "coolCat55",
            givenName: "John",
            familyName: "Doe",
            gender: "male"
        ),
        redirectUrl: URL(string: "https://www.example.com/redirect")!,
        scope: ["openid", "profile", "email"]
    )

    switch signupFlow {
    case .AchievedLogin(authToken: let authToken):
        // Signup completed and user is logged in
        // Use authToken as needed
    case .AwaitingIdentifierVerification:
        // Signup completed but email/phone verification is required
    }
} catch {
    // Handle ReachFive error
}
