import Reach5

let scope = ["openid", "email", "profile", "phone", "full_write", "offline_access"]

AppDelegate.reachfive()
  .mfaStart(stepUp(
        authType: "email",
        scope: scope,
        authToken: profileAuthToken))
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }
