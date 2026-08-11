if #available(iOS 18.0, *) {
    do {
        let upgraded = try await AppDelegate.reachfive().upgradeToPasskey(withRequest: NewPasskeyRequest(presenting: presenting, friendlyName: friendlyName), authToken: authToken)
        // upgraded == false when the system declined: nothing to show the user
    } catch {
        // return ReachFive error on failure
    }
}
