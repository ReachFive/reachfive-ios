import Foundation

extension URL {
    /// Valeur du paramètre de query `name`, ou `nil` s'il est absent.
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: true)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    /// Le `code` d'autorisation de ce callback OAuth, ou une `TechnicalError` portant l'`ApiError`
    /// décrit par les paramètres du callback (`error`, `error_description`…).
    func authorizationCode() throws -> String {
        let params = URLComponents(url: self, resolvingAgainstBaseURL: true)?.queryItems
        guard let code = params?.first(where: { $0.name == "code" })?.value else {
            throw ReachFiveError.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params))
        }
        return code
    }
}
