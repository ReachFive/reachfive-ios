import Reach5

Task {
    do {
        let authToken = try await AppDelegate.reachfive().signup(
            profile: ProfileSignupRequest(
                givenName: "John",
                familyName: "Doe",
                gender: "male",
                email: "john.doe@gmail.com",
                customIdentifier: "coolCat55",
                password: "hjk90wxc"
            ),
            redirectUrl: "https://www.example.com/redirect",
            scope: ["openid", "profile", "email"]
        )
        // Get the profile's authentication token
    } catch {
        // Return a ReachFive error
    }
}