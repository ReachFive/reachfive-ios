Task {
    do {
        let authToken = try await AppDelegate.reachfive().loginWithPassword(
            email: "john.doe@gmail.com",
            password: "UCrcF4RH",
            scope: ["openid", "profile", "email"]
        )
        // Get the profile's authentication token
    } catch {
        // Return a ReachFive error
    }
}