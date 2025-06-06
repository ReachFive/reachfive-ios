import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

AppDelegate
  .reachfive()
  .verifyEmail(
      authToken: profileAuthToken,
      email: "johnatthan.doe@gmail.com",
      code: "123456"
  )
  .onSuccess { _ in
    // Successfully verified email
  }
  .onFailure { error in
    // Return a ReachFive error
  }
  