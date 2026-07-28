import Foundation

/// Comment une `ASWebAuthenticationSession` se termine : par le custom scheme du SDK, ou par un lien
/// universel intercepté dans la feuille. Utiliser les fabriques ci-dessous.
///
/// Il n'y a **pas** d'axe « in-band vs hors-bande » : un provider peut décider en vol, feuille déjà
/// ouverte, de rester dans la feuille ou de sortir vers une app externe (b.connect choisit
/// `passive`/`active` après le `/authorize`). L'appelant ne peut donc pas trancher, et n'a pas à le
/// faire : ``customScheme`` arme les deux canaux à la fois.
///
/// **Pourquoi un `struct` et pas un `enum`** : seul ``universalLink(_:)`` exige iOS 17.4+, et Swift
/// refuse `@available` sur un cas d'énumération porteur d'une valeur associée (contrairement à un cas
/// nu comme `ModalAuthorization.Passkey`). Une fabrique statique, elle, peut l'être — c'est ce qui
/// garde la contrainte de version vérifiée **à la compilation** plutôt que reportée au runtime.
public struct WebSessionMode {
    enum Callback {
        case customScheme
        case universalLink(URL)
    }

    let callback: Callback

    private init(callback: Callback) {
        self.callback = callback
    }

    /// Retour par le custom scheme du SDK (`reachfive-<clientId>://callback`), que la redirection
    /// finale soit interceptée dans la feuille ou livrée par le navigateur par défaut à
    /// `application(_:open:)`. Défaut, sur toutes les versions d'iOS supportées.
    public static let customScheme = WebSessionMode(callback: .customScheme)

    /// Retour par un lien universel intercepté dans la feuille (via `callback: .https`).
    /// Associated Domain `webcredentials:<host>` requis ; `link` est la `redirect_uri` attendue.
    ///
    /// **Pas de dégradation gracieuse sous iOS 17.4** : la redirection finale vers
    /// `https://<host>/<path>?code=…` a lieu *dans la feuille*, et iOS ne suit pas un lien universel
    /// sur une navigation qui n'est pas initiée par l'utilisateur. Sans `callback: .https`, la feuille
    /// chargerait la page de callback, `application(_:continue:)` ne serait jamais appelé, et le login
    /// resterait suspendu jusqu'à annulation. Le seul mécanisme capable de produire ce retour
    /// hors-bande serait une app externe appelant `UIApplication.open` — ce que le flow réel ne fait
    /// pas : l'app externe rouvre le *navigateur par défaut*, pas l'app hôte.
    @available(iOS 17.4, *)
    public static func universalLink(_ link: URL) -> WebSessionMode {
        WebSessionMode(callback: .universalLink(link))
    }

    /// La `redirect_uri` portée par le mode ; `nil` pour le custom scheme, où celle du `SdkConfig` s'applique.
    var redirectUri: URL? {
        switch callback {
        case .customScheme: nil
        case .universalLink(let url): url
        }
    }
}
