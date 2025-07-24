import Reach5

do {
    try await AppDelegate.reachfive().updatePassword(
        .SmsParams(
            phoneNumber: "+33682234940",
            verificationCode: "234",
            password: "ZPf7LFtc"
        )
    )
    // Do something
} catch {
    // Return a ReachFive error
}