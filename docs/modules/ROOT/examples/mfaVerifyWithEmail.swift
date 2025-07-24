import Reach5

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