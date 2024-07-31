import Reach5

AppDelegate.reachfive()
  .mfaStart(stepUp(
        challengeId: "m3DaoT...7Rzp1m",
        verificationCode: "123456",
        trustDevice: true))
  .onSuccess{ _ in
      // Do something
  }
  .onFailure { error in
      // Return a ReachFive error
  }
