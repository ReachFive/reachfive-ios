import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

AppDelegate
    .reachfive()
    .getProfile(authToken: profileAuthToken)
    .onSuccess { profile in
      // Get the profile
    }
    .onFailure { error in
      // Return a ReachFive error
    }
