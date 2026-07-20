import Foundation

/// Describes how an `ASWebAuthenticationSession` ends — hence **how it's built** and
/// **which channel receives the callback**. Two orthogonal axes:
///
/// - ``Callback``: the shape of the redirection the SDK waits for — a **custom scheme**
///   (delivered to the app through `application(_:open:)`) or an **HTTPS universal link**
///   (delivered through `application(_:continue:)`).
/// - ``Channel``: where the redirection is intercepted — **in-band**, inside the session's own
///   webview (which then fires its completion handler), or **out-of-band**, when the flow hands
///   off to an external app that reopens the host app.
///
/// Only the four meaningful combinations are reachable, exposed as named factories (the memberwise
/// init is private). The in-sheet universal link is the sole combination that requires iOS 17.4+,
/// and its factory is annotated accordingly.
public struct WebSessionMode {
    enum Callback {
        /// Custom scheme (e.g. `reachfive-<clientId>`). `redirect_uri` = the `SdkConfig`'s.
        case customScheme
        /// HTTPS universal link. `redirect_uri` = the carried URL.
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

    /// Custom scheme intercepted _inside_ the sheet — the historical flow, on every iOS version.
    public static let sdkScheme = WebSessionMode(callback: .customScheme, channel: .inBand)

    /// out-of-band: an external app reopens the host app via the custom scheme, delivered through
    /// `application(_:open:)`. The expected `redirect_uri` is the `SdkConfig`'s.
    public static let externalAppScheme = WebSessionMode(callback: .customScheme, channel: .outOfBand)

    /// out-of-band: an external app reopens the host app via a universal link, delivered through
    /// `application(_:continue:)`. Requires the `applinks:<host>` Associated Domain. `link` is the
    /// expected `redirect_uri`, recognized by `tryComplete`.
    public static func externalAppUniversalLink(_ link: URL) -> WebSessionMode {
        WebSessionMode(callback: .universalLink(link), channel: .outOfBand)
    }

    /// Universal link intercepted _inside_ the webview (iOS 17.4+ via `callback: .https`). Requires the
    /// `webcredentials:<host>` Associated Domain. Reserve for flows that stay within the sheet (no jump
    /// to an external app). `link` is the expected `redirect_uri`.
    @available(iOS 17.4, *)
    public static func inSheetUniversalLink(_ link: URL) -> WebSessionMode {
        WebSessionMode(callback: .universalLink(link), channel: .inBand)
    }

    /// The OAuth `redirect_uri` carried by the mode; `nil` for a custom scheme, where the `SdkConfig`'s
    /// applies instead (both to `/authorize` and to the code exchange).
    var redirectUri: URL? {
        switch callback {
        case .customScheme: nil
        case .universalLink(let url): url
        }
    }
}
