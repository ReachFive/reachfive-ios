import IdentitySdkCore

AppDelegate.reachfive()
  .startPasswordless(.Email(email: "john.doe@gmail.com", redirectUri: "reachfive-${clientId}://callback"))
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }
