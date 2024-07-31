import Reach5

AppDelegate.reachfive()
  .mfaVerify(.PhoneNumber,
        authToken: profileAuthToken,
        code: verificationCode)
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }
