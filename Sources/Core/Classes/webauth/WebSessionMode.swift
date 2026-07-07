import Foundation

/// Describes how an `ASWebAuthenticationSession` ends — hence **how it's built** and
/// **which channel receives the callback**.
/// Two channels, mutually exclusive for a given login:
/// - **in-band** (``sdkScheme`` & ``universalLink``): the final redirection is intercepted INSIDE the session's webview,
///   which then triggers its completion handler.
/// - **out-of-band** (``externalApp``): the flow ends in an external app that reopens the host app
///   via a universal link (`application(_:continue:)` → ``WebAuthenticationSession/tryComplete(externalCallbackURL:)``);
///   the session never sees this callback, so it's opened as a plain web host and then cancelled.
public enum WebSessionMode {
    /// Custom scheme intercepted by the session (works on all iOS versions). E.g. `reachfive-<clientId>`.
    case sdkScheme

    /// Universal link intercepted INSIDE the webview (iOS 17.4+ via `callback: .https`). Requires
    /// the `webcredentials:<host>` Associated Domain. Reserve for flows that end
    /// entirely within the sheet (no jump to an external app).
    case universalLink(URL)

    /// OUT-OF-BAND completion: universal link returned by an external app. Requires
    /// the `applinks:<host>` Associated Domain on the host app side. The carried value is the expected
    /// `redirect_uri`, recognized by `tryComplete`.
    case externalApp(URL)

    /// The universal link expected OUT-OF-BAND (via `tryComplete`), `nil` in in-band mode.
    var outOfBandCallback: URL? {
        switch self {
        case .externalApp(let url): url
        case .sdkScheme, .universalLink: nil
        }
    }

    /// The OAuth `redirect_uri` carried by the mode; `nil` for ``sdkScheme``, where the `SdkConfig`'s
    /// applies instead (both to `/authorize` and to the code exchange).
    var redirectUri: String? {
        switch self {
        case .externalApp(let url), .universalLink(let url): url.absoluteString
        case .sdkScheme: nil
        }
    }
}
