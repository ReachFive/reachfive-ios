import Reach5

let verifyAuthCodeRequest = VerifyAuthCodeRequest(
  email: emailInput,
  verificationCode: verificationCodeInput
)

Task {
    do {
        let authToken = try await AppDelegate.reachfive().verifyPasswordlessCode(verifyAuthCodeRequest: verifyAuthCodeRequest)
        // Do something
    } catch {
        // Return a ReachFive error
    }
}