import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

AppDelegate
  .reachfive()
  .updateProfile(
      authToken: profileAuthToken,
      profileUpdate: ProfileUpdate(phoneNumber: .Delete)
  )
  .onSuccess { updatedProfile in
    // Get the updated profile
  }
  .onFailure { error in
    // Return a ReachFive error
  }
