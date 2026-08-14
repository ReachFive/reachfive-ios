import Foundation
import Reach5URLValidation

extension URL {
    /// Value of the `name` query parameter, or `nil` if absent.
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: true)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    /// `true` when this URL designates the same endpoint as `expected`: same scheme and same host
    /// (both through `normalizedScheme`/`normalizedHost`, which apply the case folding RFC 3986 requires and
    /// Foundation does not), and the same normalized path.
    ///
    /// `""` and `"/"` are treated as the same path: a browser routinely appends the trailing slash to an
    /// authority-only URL, so a callback declared as `reachfive-<clientId>://callback` can be delivered
    /// back as `reachfive-<clientId>://callback/`.
    ///
    /// This is the SDK's single matcher for its own callback URIs, shared by
    /// ``ReachFive/interceptUrl(_:)`` and `WebAuthenticationSession.isOurCallback`, so that the two entry
    /// hooks can never disagree on what is or isn't ours.
    func matchesEndpoint(of expected: URL) -> Bool {
        normalizedScheme == expected.normalizedScheme
            && normalizedHost == expected.normalizedHost
            && Self.normalizedPath(path) == Self.normalizedPath(expected.path)
    }

    private static func normalizedPath(_ path: String) -> String {
        path == "/" ? "" : path
    }

    /// The authorization `code` of this OAuth callback, or a `TechnicalError` carrying the `ApiError`
    /// described by the callback's parameters (`error`, `error_description`…).
    func authorizationCode() throws -> String {
        let params = URLComponents(url: self, resolvingAgainstBaseURL: true)?.queryItems
        guard let code = params?.first(where: { $0.name == "code" })?.value else {
            throw ReachFiveError.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params))
        }
        return code
    }
}
