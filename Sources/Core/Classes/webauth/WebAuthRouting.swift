import Foundation

/// Critère de reconnaissance d'un callback de login web : permet de savoir si une URL entrante (reçue
/// via `application(_:continue:)`) est le callback d'auth d'une session donnée — par opposition à un
/// autre universal link que l'app hôte nous transmet.
///
/// On s'appuie sur le paramètre OAuth `state`, généré par le SDK pour ce login et ré-émis verbatim par
/// le backend dans la redirection (y compris à travers un provider fédéré comme B.connect). Ce n'est PAS
/// un mécanisme de sécurité — la CSRF est couverte par PKCE — mais une clé de corrélation côté client :
/// reconnaître notre propre callback, et ignorer un callback périmé d'une tentative précédente.
struct WebAuthRouting: Equatable {
    /// Clé de corrélation générée par le SDK pour ce login, envoyée comme `state` à `/authorize` et attendue en retour.
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
