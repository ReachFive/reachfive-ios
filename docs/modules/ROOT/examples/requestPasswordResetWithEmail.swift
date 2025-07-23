Task {
    do {
        try await AppDelegate.reachfive().requestPasswordReset(
            email: "john.doe@gmail.com",
            redirectUrl: "reachfive-clientId://password-reset"
        )
        // Do something
    } catch {
        // Return a ReachFive error
    }
}