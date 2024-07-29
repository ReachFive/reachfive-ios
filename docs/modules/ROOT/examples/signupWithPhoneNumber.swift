import IdentitySdkCore

AppDelegate
  .reachfive()
  .signup(
      profile: ProfileSignupRequest(
        givenName: "John",
        familyName: "Doe",
        gender: "male",
        phoneNumber: "+353875551234",
        customIdentifier: "coolCat55",
        password: "hjk90wxc"
      ),
      redirectUrl: "https://www.example.com/redirect",
      scope: ["openid", "profile", "phone"]
  )
  .onSuccess{ authToken in
      // Get the profile's authentication token
  }
  .onFailure { error in
      // Return a ReachFive error
  }