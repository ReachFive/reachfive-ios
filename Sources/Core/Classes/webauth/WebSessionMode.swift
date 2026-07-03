import Foundation

/// Décrit comment une `ASWebAuthenticationSession` se termine — donc **comment on la construit** et
/// **par quel canal on reçoit le callback**.
/// Deux canaux, mutuellement exclusifs pour un même login :
/// - **in-band** (``scheme`` & ``universalLink``) : la redirection finale est interceptée DANS la webview de la session,
///   qui déclenche alors son completion handler.
/// - **hors-bande** (``externalApp``) : le flow se termine dans une app externe qui rouvre l'app hôte
///   via un universal link (`application(_:continue:)` → ``WebAuthenticationSession/tryComplete(externalCallbackURL:)``) ;
///   la session ne voit jamais ce callback, on l'ouvre en simple hôte web puis on l'annule.
public enum WebSessionMode {
    /// Scheme custom intercepté par la session (historique, tout iOS). Ex. `reachfive-<clientId>`.
    case sdkScheme
    
    /// Universal link intercepté DANS la webview (iOS 17.4+ via `callback: .https`). Requiert
    /// l'Associated Domain `webcredentials:<host>`. À réserver aux flows qui se terminent
    /// entièrement dans la feuille (aucun saut vers une app externe).
    case universalLink(URL)
    
    /// Complétion HORS-BANDE : universal link renvoyé par une app externe (ex. B.connect). Requiert
    /// l'Associated Domain `applinks:<host>` côté app hôte. La valeur portée est le `redirect_uri`
    /// attendu, reconnu par `tryComplete`.
    case externalApp(URL)
    
    /// Le universal link attendu HORS-BANDE (via `tryComplete`), `nil` en mode in-band.
    var outOfBandCallback: URL? {
        switch self {
        case .externalApp(let url): url
        default: nil
        }
    }
    var redirectUri: String? {
        switch self {
        case .externalApp(let url): url.absoluteString
        case .universalLink(let url): url.absoluteString
        default: nil
        }
    }
}
