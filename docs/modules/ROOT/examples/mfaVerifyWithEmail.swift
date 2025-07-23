import Reach5

Task {
    do {
        let credential = try await AppDelegate.reachfive().mfaVerify(
            .Email,
            code: verificationCode,
            authToken: profileAuthToken
        )
        // Do something
    } catch {
        // Return a ReachFive error
    }
}