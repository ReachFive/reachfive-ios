import IdentitySdkCore

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

AppDelegate
  .reachfive()
  .updateProfile(
      authToken: profileAuthToken,
      profile: Profile(givenName: "Jonathan", phoneNumber: "+33750253354")
  )
  .onSuccess { updatedProfile in
    // Get the updated profile
  }
  .onFailure { error in
    // Return a ReachFive error
  }