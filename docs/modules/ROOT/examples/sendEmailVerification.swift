import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

do {
    let emailVerificationResponse = try await AppDelegate.reachfive().sendEmailVerification(
        authToken: profileAuthToken,
        redirectUrl: "https://example-email-verification.com" // optional
    )
    switch emailVerificationResponse {
    case .Success:
        // Email verification process completed successfully
    case .VerificationNeeded(let continueEmailVerification):
        // Verification email sent, use continueEmailVerification.verify(code: String, email: String, freshAuthToken: AuthToken? = nil) or AppDelegate.reachfive().verifyEmail to complete the flow
    }
} catch {
    // Return a ReachFive error
}