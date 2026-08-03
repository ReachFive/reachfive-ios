import XCTest
@testable import Reach5

/// `WebAuthenticationSession`'s lifecycle, for the little of it that is reachable without presenting a sheet.
@MainActor
final class WebAuthenticationSessionTests: XCTestCase {

    private func makeSession() -> WebAuthenticationSession {
        WebAuthenticationSession(baseScheme: "reachfive-clientId",
                                 sdkRedirectUri: URL(string: "reachfive-clientId://callback")!)
    }

    /// Outside a login the out-of-band channel is not armed, even for a URL perfectly shaped for this SDK:
    /// what decides is `expectedCallback` (nil at rest), not the shape of the URL. The host app must get its
    /// link back (`false`), not see it swallowed by the SDK.
    func testTryCompleteMatchesNothingOutsideALogin() {
        let session = makeSession()
        for url in ["reachfive-clientId://callback?code=abc",
                    "reachfive-clientId://callback?code=abc&state=x",
                    "reachfive-clientId://callback/?code=abc",
                    "reachfive-clientId://callback?error=access_denied"] {
            XCTAssertFalse(session.tryComplete(externalCallbackURL: URL(string: url)!), url)
        }
    }

    /// A login refused for an unusable universal-link callback must not hold the slot. This is the one
    /// failure path reachable without presenting a sheet, so it is the one that can guard the rule the slot
    /// depends on: nothing claims it before the call is certain to go through.
    ///
    /// The tell is *which* error comes back the second time. `TechnicalError` means the call reached the
    /// callback check again, so the slot was free; `AuthCanceled` would mean the first call kept it and the
    /// SDK is now refusing every web login for the rest of the process.
    func testAnUnusableUniversalLinkCallbackDoesNotHoldTheSlot() async throws {
        guard #available(iOS 17.4, *) else {
            throw XCTSkip("`.universalLink` requires iOS 17.4")
        }
        let session = makeSession()
        // A callback with no host: the session cannot be built, and `start` gives up before presenting.
        let mode = WebSessionMode.universalLink(URL(string: "https:///universal_link")!)
        let authorizeURL = URL(string: "https://example.reach5.net/oauth/authorize")!
        let contextProvider = DummyContextProvider()

        for attempt in 1...2 {
            do {
                _ = try await session.start(url: authorizeURL,
                                            mode: mode,
                                            presentationContextProvider: contextProvider)
                XCTFail("start should have thrown on attempt \(attempt)")
            } catch let error as ReachFiveError {
                switch error {
                case .TechnicalError:
                    break
                case .AuthCanceled:
                    XCTFail("attempt \(attempt) was dropped as if a login were already in progress: the slot leaked")
                default:
                    XCTFail("attempt \(attempt) failed with an unexpected error: \(error)")
                }
            }
        }
    }
}
