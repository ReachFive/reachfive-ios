import Foundation

//TODO: utiliser ces utilitaires pour simplifier le code existant
extension URL {
    /// Valeur du paramètre de query `name`, ou `nil` s'il est absent.
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: true)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    /// Segments de path non vides. `""` et `"/"` donnent `[]` (pas de joker).
    var pathSegments: [String] {
        path.split(separator: "/").map(String.init)
    }
}
