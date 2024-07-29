import Reach5

AppDelegate.reachfive()
  .mfaListCredentials(authToken: profileAuthToken)
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }
