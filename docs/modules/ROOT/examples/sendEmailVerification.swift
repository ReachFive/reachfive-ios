import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

AppDelegate
  .reachfive()
  .sendEmailVerification(
      authToken: profileAuthToken,
      redirectUrl: "https://example-email-verification.com" // optional
  )
  .onSuccess { emailVerificationResponse in
    switch emailVerificationResponse {
      case .Success:
        // Email verification process completed successfully
      case .VerificationNeeded(let continueEmailVerification):
        // Verification email sent, use continueEmailVerification.verify(code: String, email: String, freshAuthToken: AuthToken? = nil) or AppDelegate.reachfive().verifyEmail to complete the flow
    }
  }
  .onFailure { error in
    // Return a ReachFive error
  }