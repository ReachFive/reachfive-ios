import Reach5

do {
    try await AppDelegate.reachfive().updatePassword(
        .EmailParams(
            email: "john.doe@example.com",
            verificationCode: "234",
            password: "ZPf7LFtc"
        )
    )
    // Do something
} catch {
    // Return a ReachFive error
}