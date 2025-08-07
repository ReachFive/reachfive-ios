import Foundation
import AuthenticationServices

public class WebSessionLogoutRequest {
    public let presentationContextProvider: ASWebAuthenticationPresentationContextProviding
    public let origin: String?

    public init(presentationContextProvider: ASWebAuthenticationPresentationContextProviding, origin: String? = nil) {
        self.presentationContextProvider = presentationContextProvider
        self.origin = origin
    }
}
