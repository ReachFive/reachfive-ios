import Foundation

extension URL {
    /// Value of the `name` query parameter, or `nil` if absent.
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: true)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
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
