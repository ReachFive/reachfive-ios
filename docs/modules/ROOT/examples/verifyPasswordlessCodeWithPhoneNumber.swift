import Reach5

let verifyAuthCodeRequest = VerifyAuthCodeRequest(
  phoneNumber: phoneNumberInput,
  verificationCode: verificationCodeInput
)

do {
    let authToken = try await AppDelegate.reachfive().verifyPasswordlessCode(verifyAuthCodeRequest: verifyAuthCodeRequest)
    // Do something
} catch {
    // Return a ReachFive error
}