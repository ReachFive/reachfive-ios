import Reach5

let scope = ["openid", "email", "profile", "phone", "full_write", "offline_access"]

AppDelegate.reachfive()
  .mfaStart(stepUp: StartStepUp.LoginFlow(
        authType: "email",
        stepUpToken: "stepUpToken123",
        origin: "ios-app",
        redirectUri: "https://example.com/callback",))
  .onSuccess { _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }
