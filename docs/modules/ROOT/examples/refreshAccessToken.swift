import IdentitySdkCore

val authToken: AuthToken = // The authentication token obtained from login or signup.

AppDelegate.reachfive()
      .refreshAccessToken(authToken)
      .onSuccess{ refreshedAuthToken in
        // Do something
      }
      .onFailure { error in
        // Return a ReachFive error
      }