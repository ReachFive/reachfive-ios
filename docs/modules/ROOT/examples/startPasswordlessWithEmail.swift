import Reach5

Task {
    do {
        try await AppDelegate.reachfive().startPasswordless(.Email(email: "john.doe@gmail.com")
        // Do something
    } catch {
        // Return a ReachFive error
    }
}
