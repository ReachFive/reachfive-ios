do {
    try await AppDelegate.reachfive().resetPasskeys(withRequest: ResetPasskeyRequest(verificationCode: verificationCode, friendlyName: friendlyName, presenting: presenting, email: email))
    // handle success
} catch {
    // return ReachFive error on failure
}