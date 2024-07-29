import IdentitySdkCore

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

AppDelegate
  .reachfive()
  .updateEmail(
      authToken: profileAuthToken,
      email: "johnatthan.doe@gmail.com",
      redirectUrl: "https://example-email-update.com"
  )
  .onSuccess { updatedProfile in
    // Get the updated profile
  }
  .onFailure { error in
    // Return a ReachFive error
  }