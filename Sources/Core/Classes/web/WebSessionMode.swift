import Foundation

/// How an `ASWebAuthenticationSession` ends: through the SDK's custom scheme, or through a universal link
/// intercepted in the sheet. Use the factories below.
///
/// **Why a `struct` and not an `enum`**: only ``universalLink(_:)`` requires iOS 17.4+, and Swift refuses
/// `@available` on an enum case carrying an associated value (unlike a bare case such as
/// `ModalAuthorization.Passkey`). A static factory can carry it — which is what keeps the version
/// constraint checked **at compile time** rather than deferred to runtime.
public struct WebSessionMode {
    enum Callback {
        case customScheme
        case universalLink(URL)
    }

    let callback: Callback

    private init(callback: Callback) {
        self.callback = callback
    }

    /// Return through the SDK's custom scheme (`reachfive-<clientId>://callback`), whether the final
    /// redirection is intercepted in the sheet or delivered by the default browser to
    /// `application(_:open:)`. The default, on every supported iOS version.
    public static let customScheme = WebSessionMode(callback: .customScheme)

    /// Return through a universal link intercepted in the sheet (via `callback: .https`). Requires the
    /// `webcredentials:<host>` Associated Domain; `link` is the expected `redirect_uri`.
    @available(iOS 17.4, *)
    public static func universalLink(_ link: URL) -> WebSessionMode {
        WebSessionMode(callback: .universalLink(link))
    }

    /// The `redirect_uri` carried by the mode; `nil` for the custom scheme, where the `SdkConfig`'s applies.
    var redirectUri: URL? {
        switch callback {
        case .customScheme: nil
        case .universalLink(let url): url
        }
    }
}
