import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

AppDelegate
  .reachfive()
  .verifyPhoneNumber(
      authToken: profileAuthToken,
      phoneNumber: "+33750253354",
      verificationCode: "501028"
  )
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }
