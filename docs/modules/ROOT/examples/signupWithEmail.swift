import Reach5

AppDelegate
  .reachfive()
  .signup(
      profile: ProfileSignupRequest(
        givenName: "John",
        familyName: "Doe",
        gender: "male",
        email: "john.doe@gmail.com",
        customIdentifier: "coolCat55",
        password: "hjk90wxc"
      ),
      redirectUrl: "https://www.example.com/redirect",
      scope: ["openid", "profile", "email"]
  )
  .onSuccess{ authToken in
      // Get the profile's authentication token
  }
  .onFailure { error in
      // Return a ReachFive error
  }
