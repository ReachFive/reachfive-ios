import Foundation
import AuthenticationServices

public class WebSessionLogoutRequest {
    public let presentationContextProvider: ASWebAuthenticationPresentationContextProviding
    public let origin: String?

    public init(presentationContextProvider: ASWebAuthenticationPresentationContextProviding, origin: String? = nil) {
        self.presentationContextProvider = presentationContextProvider
        self.origin = origin
    }

    /// Same as ``init(presentationContextProvider:origin:)``, but derives the presentation
    /// context from a ``Presentation``, so the view controller does not need to conform
    /// to `ASWebAuthenticationPresentationContextProviding`.
    ///
    /// - Throws: `ReachFiveError.TechnicalError` if the view controller has been deallocated.
    @MainActor
    public convenience init(presenting: Presentation, origin: String? = nil) throws {
        self.init(presentationContextProvider: try presenting.webAuthContextProvider(), origin: origin)
    }
}
