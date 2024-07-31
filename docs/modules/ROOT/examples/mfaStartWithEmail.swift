import Reach5

AppDelegate.reachfive()
  .mfaStart(.Email(
        redirectUri: "reachfive-${clientId}://callback"),
        authToken: profileAuthToken)
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }
