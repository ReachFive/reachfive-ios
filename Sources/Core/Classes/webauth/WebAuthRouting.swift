import Foundation

/// Critère de reconnaissance d'un callback de login web, pour router un retour (in-band ou universal
/// link out-of-band) vers la bonne session en vol.
///
/// Le routage se fait sur le paramètre OAuth `state`, unique par login : le backend le ré-émet
/// verbatim dans la redirection — y compris à travers un provider fédéré comme B.connect — donc il
/// est toujours présent et identifie la session sans ambiguïté.
struct WebAuthRouting: Equatable {
    /// Token unique de ce login, envoyé comme `state` à `/authorize` et attendu en retour.
    let state: String
    /// Le `redirect_uri` OAuth attendu, déjà parsé. Sert au callback `.https` in-band (host/path), pas au routage.
    let expectedCallback: URL?

    init(state: String, expectedCallback: URL?) {
        self.state = state
        self.expectedCallback = expectedCallback
    }

    /// `true` si l'URL de callback entrante porte le `state` de ce login.
    func matches(_ incoming: URL) -> Bool {
        incoming.queryValue("state") == state
    }
}
