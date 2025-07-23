Task {
    do {
        try await AppDelegate.reachfive().requestPasswordReset(phoneNumber: "+33682234940")
        // Do something
    } catch {
        // Return a ReachFive error
    }
}