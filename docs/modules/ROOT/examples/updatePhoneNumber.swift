import IdentitySdkCore

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

AppDelegate
  .reachfive()
  .updatePhoneNumber(
      authToken: profileAuthToken,
      phoneNumber: "+33792244940"
  )
  .onSuccess { updatedProfile in
    // Get the updated profile
  }
  .onFailure { error in
    // Return a ReachFive error
  }