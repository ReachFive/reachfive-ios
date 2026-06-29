import Foundation

/// Critère de reconnaissance d'un callback de login web, utilisé pour router un retour
/// (in-band ou universal link out-of-band) vers la bonne session en vol.
///
/// La clé primaire est le paramètre OAuth `state`, unique par login et ré-émis verbatim par le
/// backend dans la redirection (y compris à travers un provider fédéré comme B.connect). Un
/// fallback par URL (host insensible à la casse + préfixe de path par segments) couvre le cas —
/// non attendu — où le `state` serait absent du callback.
struct WebAuthRouting: Equatable {
    /// Token unique de ce login, envoyé comme `state` à `/authorize` et attendu en retour.
    let state: String
    /// Le `redirect_uri` OAuth attendu, déjà parsé (source de vérité unique pour host/path).
    let expectedCallback: URL?

    init(state: String, expectedCallback: URL?) {
        self.state = state
        self.expectedCallback = expectedCallback
    }

    /// `true` si l'URL de callback entrante correspond à ce login.
    func matches(_ incoming: URL) -> Bool {
        // 1. Routage non ambigu par `state` : s'il est présent, il fait autorité.
        if let incomingState = incoming.queryValue("state") {
            return incomingState == state
        }
        //TODO: y a-t-il besoin d'avoir ça car le state est toujours présent ?
        // 2. Fallback : même host (insensible à la casse) et préfixe de path par segments.
        guard let expectedCallback,
              let expectedHost = expectedCallback.host?.lowercased(),
              let incomingHost = incoming.host?.lowercased(),
              expectedHost == incomingHost
        else { return false }

        let expectedSegments = expectedCallback.pathSegments
        guard !expectedSegments.isEmpty else { return false } // un path vide n'est pas un joker
        return incoming.pathSegments.starts(with: expectedSegments)
    }
}
