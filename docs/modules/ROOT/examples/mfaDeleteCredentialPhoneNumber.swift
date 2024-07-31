import Reach5

AppDelegate.reachfive()
  .mfaDeleteCredential(
    phoneNumber: "+33682234940",
    authToken: profileAuthToken
)
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }
