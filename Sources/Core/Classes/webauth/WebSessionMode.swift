import Foundation

/// How an `ASWebAuthenticationSession` completes, on two orthogonal axes: the ``Callback`` shape (custom
/// scheme, delivered via `application(_:open:)`, or universal link, via `application(_:continue:)`) and
/// the ``Channel`` where it's intercepted (in the session's webview, or out-of-band via an external app).
/// Use the factories below; only the in-sheet universal link needs iOS 17.4+.
public struct WebSessionMode {
    enum Callback {
        case customScheme
        case universalLink(URL)
    }

    public enum Channel {
        /// The redirection is intercepted _inside_ the session's webview.
        case inBand
        /// The flow ends in an external app that reopens the host app.
        case outOfBand
    }

    let callback: Callback
    let channel: Channel

    private init(callback: Callback, channel: Channel) {
        self.callback = callback
        self.channel = channel
    }

    /// Custom scheme intercepted in the sheet — the historical flow, on every iOS version.
    public static let sdkScheme = WebSessionMode(callback: .customScheme, channel: .inBand)

    /// An external app reopens the host app via the custom scheme.
    public static let externalAppScheme = WebSessionMode(callback: .customScheme, channel: .outOfBand)

    /// An external app reopens the host app via a universal link. Requires the `applinks:<host>`
    /// Associated Domain; `link` is the expected `redirect_uri`.
    public static func externalAppUniversalLink(_ link: URL) -> WebSessionMode {
        WebSessionMode(callback: .universalLink(link), channel: .outOfBand)
    }

    /// Universal link intercepted in the sheet (via `callback: .https`). Requires the
    /// `webcredentials:<host>` Associated Domain; `link` is the expected `redirect_uri`.
    @available(iOS 17.4, *)
    public static func inSheetUniversalLink(_ link: URL) -> WebSessionMode {
        WebSessionMode(callback: .universalLink(link), channel: .inBand)
    }

    /// The OAuth `redirect_uri` carried by the mode; `nil` for a custom scheme, where the `SdkConfig`'s applies.
    var redirectUri: URL? {
        switch callback {
        case .customScheme: nil
        case .universalLink(let url): url
        }
    }
}
