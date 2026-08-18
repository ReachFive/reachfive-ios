import Foundation

extension URL {
    /// Value of the `name` query parameter, or `nil` if absent.
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: true)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    /// `true` when this URL designates the same endpoint as `expected`: same scheme, same host, same
    /// normalized path (the three `normalized…` accessors, which apply what RFC 3986 requires and
    /// Foundation does not).
    func matchesEndpoint(of expected: URL) -> Bool {
        normalizedScheme == expected.normalizedScheme
            && normalizedHost == expected.normalizedHost
            && normalizedPath == expected.normalizedPath
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
