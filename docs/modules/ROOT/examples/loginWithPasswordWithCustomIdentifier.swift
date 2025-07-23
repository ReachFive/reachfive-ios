Task {
    do {
        let authToken = try await AppDelegate.reachfive().loginWithPassword(
            customIdentifier: "coolCat55",
            password: "UCrcF4RH",
            scope: ["openid", "profile", "email"]
        )
        // Get the profile's authentication token
    } catch {
        // Return a ReachFive error
    }
}