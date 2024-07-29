import Reach5

AppDelegate.reachfive()
  .mfaStart(.PhoneNumber(
        phoneNumber: "+3531235555"),
        authToken: profileAuthToken)
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }
