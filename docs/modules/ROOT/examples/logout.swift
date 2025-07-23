Task {
    do {
        try await AppDelegate.reachfive().logout()
        // Do something
    } catch {
        // Return a ReachFive error
    }
}