import IdentitySdkCore

AppDelegate.reachfive()
  .startPasswordless(.PhoneNumber(phoneNumber: "+33792244940", redirectUri: "reachfive-${clientId}://callback"))
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }