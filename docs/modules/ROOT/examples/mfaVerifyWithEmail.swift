import IdentitySdkCore

AppDelegate.reachfive()
  .mfaVerify(.Email,
        authToken: profileAuthToken,
        code: verificationCode)
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }