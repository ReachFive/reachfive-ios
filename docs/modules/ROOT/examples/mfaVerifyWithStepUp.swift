import Reach5

Task {
    do {
        let authToken = try await AppDelegate.reachfive().mfaVerify(
            stepUp: VerifyStepUp(
                challengeId: "m3DaoT...7Rzp1m",
                verificationCode: "123456",
                trustDevice: true
            )
        )
        // Do something
    } catch {
        // Return a ReachFive error
    }
}