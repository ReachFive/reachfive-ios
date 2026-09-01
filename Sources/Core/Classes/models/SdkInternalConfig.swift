import Foundation

/// Answers an authentication challenge raised on the SDK's `URLSession`, the way a `URLSessionDelegate`
/// would: a disposition, and the credential that goes with it.
///
/// This is where an app that pins the server's certificate plugs its trust evaluation in. Doing it here
/// rather than by swizzling `URLSession` or `URLSessionConfiguration` matters: the SDK's `/oauth/authorize`
/// call ends on a redirection to the app's custom scheme that the SDK must handle itself, and an
/// interception layer answering `willPerformHTTPRedirection` in its place takes that callback away — with the
/// authorization code in it. A handler only ever sees challenges, never redirections, so it cannot break that
/// flow.
///
/// It runs off the main thread, may run concurrently with itself, and is called for every challenge on every
/// call the SDK makes. Returning `.performDefaultHandling` leaves the system's own validation in charge,
/// which is what the SDK does when no handler is given.
public typealias AuthenticationChallengeHandler = @Sendable (URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?)

public class SdkInternalConfig {
    public let loggingEnabled: Bool

    /// Called for every authentication challenge on the SDK's network calls, `nil` to leave them to the
    /// system. See ``AuthenticationChallengeHandler``.
    public let authenticationChallengeHandler: AuthenticationChallengeHandler?

    public init(loggingEnabled: Bool = false, authenticationChallengeHandler: AuthenticationChallengeHandler? = nil) {
        self.loggingEnabled = loggingEnabled
        self.authenticationChallengeHandler = authenticationChallengeHandler
    }
}
