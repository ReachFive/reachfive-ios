import Reach5

Task {
    do {
        let authToken = try await AppDelegate.reachfive().signup(
            profile: ProfileSignupRequest(
                givenName: "John",
                familyName: "Doe",
                gender: "male",
                phoneNumber: "+353875551234",
                customIdentifier: "coolCat55",
                password: "hjk90wxc"
            ),
            scope: ["openid", "profile", "phone"]
        )
        // Get the profile's authentication token
    } catch {
        // Return a ReachFive error
    }
}
