import IdentitySdkCore

AppDelegate.reachfive()
  .mfaDeleteCredential(authToken: profileAuthToken)
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }