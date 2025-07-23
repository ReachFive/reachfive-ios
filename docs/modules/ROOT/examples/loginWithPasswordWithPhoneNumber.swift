Task {
    do {
        let authToken = try await AppDelegate.reachfive().loginWithPassword(
            phoneNumber: "+33682234940",
            password: "UCrcF4RH",
            scope: ["openid", "profile", "email"]
        )
        // Get the profile's authentication token
    } catch {
        // Return a ReachFive error
    }
}