import IdentitySdkCore

let verifyAuthCodeRequest = VerifyAuthCodeRequest(
  phoneNumber: phoneNumberInput,
  verificationCode: verificationCodeInput
)
AppDelegate.reachfive()
  .verifyPasswordlessCode(verifyAuthCodeRequest: verifyAuthCodeRequest)
  .onSuccess{ _ in
    // Do something
  }
  .onFailure { error in
    // Return a ReachFive error
  }