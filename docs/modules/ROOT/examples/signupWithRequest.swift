import Reach5

AppDelegate
  .reachfive()
  .signup(withRequest: PasskeySignupRequest(passkeyPofile: profile, friendlyName: username, anchor: window))

  .onSuccess { authToken in
      // Get the profile's authentication token
  }
  .onFailure { error in
      // Return a ReachFive error
  }
