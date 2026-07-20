import AuthenticationServices

/// Porte le login web en cours : démarre une `ASWebAuthenticationSession`, attend son callback,
/// et — pour les logins hors-bande — laisse un lien reçu via `application(_:open:)` (custom scheme)
/// ou `application(_:continue:)` (lien universel) le compléter (``tryComplete(externalCallbackURL:)``).
///
/// **Un seul login à la fois.** Sur iPhone, la feuille modale d'une `ASWebAuthenticationSession` rend
/// un second `start(...)` inatteignable par l'interaction utilisateur : tant qu'elle est présentée rien
/// d'autre n'est déclenchable, et sa disparition passe par une résolution (callback, Annuler) qui reprend
/// la continuation. Restent les appels **programmatiques** (logout/login déclenché par une logique d'app
/// sans interaction, double invocation), le multi-fenêtres (iPad/macCatalyst), et un completion handler
/// que le système ne rappellerait jamais : dans tous ces cas, le dernier arrivé gagne — le login
/// précédent est repris avec `.AuthCanceled` et sa feuille est fermée, aucune continuation ne gèle.
///
/// Les callbacks tardifs ou dupliqués sont neutralisés de deux façons : un **jeton par tentative**
/// (`attempt`) — pour qu'un callback d'une `ASWebAuthenticationSession` périmée ne puisse jamais
/// reprendre la continuation d'un login plus récent — et la remise à `nil` de `continuation` dans
/// `complete(_:)` — pour que la résolution gagnante (in-band, hors-bande, ou annulation) reprenne la
/// continuation exactement une fois.
///
/// **Limitation (hors-bande)** : l'état d'un login en vol ne vit qu'en mémoire. Si iOS tue l'app
/// pendant l'aller-retour vers l'app externe, le callback reçu au relancement ne matche rien
/// (`tryComplete` renvoie `false`, l'app hôte route le lien) et le `code` est perdu : l'utilisateur
/// doit relancer le login. Une reprise après relancement demanderait de persister le login en vol
/// (redirect_uri + PKCE, déjà en storage) et un canal pour livrer le résultat à l'app — assumé hors
/// périmètre tant que l'usage ne le justifie pas.
///
/// `@MainActor` : tout le domaine `ASWebAuthenticationSession` est déjà main-thread.
@MainActor
final class WebAuthenticationSession {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    /// La `redirect_uri` attendue pour cette tentative ; `nil` hors d'un login → `tryComplete` ne matche rien.
    private var expectedCallback: URL?
    /// Identifie la tentative en cours ; un callback capturant un `attempt` périmé est ignoré.
    private var attempt = 0
    private let baseScheme: String

    nonisolated init(baseScheme: String) {
        self.baseScheme = baseScheme
    }

    /// Démarre un login web et attend son callback (succès, erreur ou annulation). Le ``WebSessionMode``
    /// décrit comment la session se termine — croisement de deux axes (custom scheme vs lien universel,
    /// in-band vs hors-bande) — et pilote donc à la fois la construction de la session et le canal du
    /// callback. `redirectUri` est la `redirect_uri` déjà résolue (celle du mode, ou à défaut celle du
    /// `SdkConfig`) : en hors-bande elle sert à reconnaître le lien entrant (``tryComplete(externalCallbackURL:)``).
    /// Si le `Task` appelant est annulé (vue démontée, timeout…), la feuille est fermée et l'appel se
    /// termine par `.AuthCanceled`.
    func start(url: URL,
               mode: WebSessionMode,
               redirectUri: URL,
               presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
               prefersEphemeralWebBrowserSession: Bool = false) async throws -> URL {

        // Un Task déjà annulé ne doit pas présenter de feuille (son `onCancel` ci-dessous aurait
        // déjà tiré, à vide, avant que la continuation soit posée).
        try Task.checkCancellation()

        // Dernier arrivé gagne : reprend l'éventuel login encore en attente avec `.AuthCanceled` et
        // ferme sa feuille, pour ne jamais laisser une continuation geler sans résolution.
        complete(attempt: attempt, .failure(.AuthCanceled))
        attempt += 1
        let attempt = attempt

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                // Seul le mode hors-bande arme `tryComplete` ; en in-band, la session se complète elle-même.
                self.expectedCallback = mode.channel == .outOfBand ? redirectUri : nil

                let completionHandler: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
                    // Tout passe sur le main thread pour éviter les situations de compétition.
                    Task { @MainActor in
                        self?.handleSessionCompletion(attempt: attempt, callbackURL: callbackURL, error: error)
                    }
                }

                let session: ASWebAuthenticationSession
                switch (mode.channel, mode.callback) {
                case (.inBand, .customScheme):
                    // Scheme custom intercepté par la session (historique, tout iOS).
                    session = ASWebAuthenticationSession(
                        url: url,
                        callbackURLScheme: self.baseScheme,
                        completionHandler: completionHandler)

                case let (.inBand, .universalLink(callback)):
                    // iOS 17.4+ : lien universel intercepté in-band dans la webview via `callback: .https`
                    // (nécessite l'Associated Domain `webcredentials:<host>`). La disponibilité est déjà
                    // garantie en amont par la fabrique `@available` de ``WebSessionMode``, on garde ici
                    // un filet runtime (et l'extraction du host, faillible).
                    guard #available(iOS 17.4, *), let host = callback.host else {
                        self.complete(attempt: attempt, .failure(.TechnicalError(reason: "In-sheet universal link callback requires iOS 17.4+ and a host: \(callback)")))
                        return
                    }
                    session = ASWebAuthenticationSession(
                        url: url,
                        callback: .https(host: host, path: callback.path),
                        completionHandler: completionHandler)

                case (.outOfBand, _):
                    // Le flow se termine dans une app externe : la session ne recevra jamais le callback
                    // (traité hors-bande par `tryComplete`, quel que soit le type de lien), on ne lui donne
                    // donc aucun scheme à intercepter.
                    session = ASWebAuthenticationSession(
                        url: url,
                        callbackURLScheme: nil,
                        completionHandler: completionHandler)
                }

                // Fenêtre qui sert d'ancre de présentation à la session.
                session.presentationContextProvider = presentationContextProvider
                session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
                self.session = session

                if !session.start() {
                    // Si start() renvoie false, le completion handler peut ne jamais être appelé : on
                    // reprend la continuation avec une erreur.
                    self.complete(attempt: attempt, .failure(.TechnicalError(reason: "ASWebAuthenticationSession failed to start")))
                }
            }
        } onCancel: {
            // L'annulation peut arriver sur n'importe quel thread → hop sur le main actor. Sans effet
            // si la tentative est déjà résolue ou remplacée par un login plus récent (gardes de `complete`).
            Task { @MainActor in
                self.complete(attempt: attempt, .failure(.AuthCanceled))
            }
        }
    }

    /// Complète le login en cours si l'URL entrante est bien notre callback, et ferme la feuille
    /// encore ouverte. Renvoie `true` seulement dans ce cas — sinon `false`, pour que l'app hôte puisse
    /// router elle-même le lien.
    func tryComplete(externalCallbackURL url: URL) -> Bool {
        guard let expectedCallback,
              Self.isOurCallback(url, expectedCallback: expectedCallback) else {
            return false
        }
        complete(attempt: attempt, .success(url))
        return true
    }

    private func handleSessionCompletion(attempt: Int, callbackURL: URL?, error: Error?) {
        if let error {
            complete(attempt: attempt, .failure(Self.reachFiveError(for: error)))
        } else if let callbackURL {
            complete(attempt: attempt, .success(callbackURL))
        } else {
            complete(attempt: attempt, .failure(.TechnicalError(reason: "No callback URL")))
        }
    }

    /// L'unique point de résolution : reprend la continuation avec `result`, nettoie l'état, et ferme
    /// la feuille si elle est encore présentée (résolution hors-bande, annulation, remplacement).
    private func complete(attempt: Int, _ result: Result<URL, ReachFiveError>) {
        // Ignore un callback périmé (login plus récent) ou une seconde résolution (`continuation` déjà nil).
        guard attempt == self.attempt, let continuation else { return }
        // Capture la session avant de la nil-er pour fermer sa feuille après la reprise. Le callback
        // d'annulation tardif qui en résulte est ignoré (continuation désormais nil) ; sur une session
        // déjà terminée ou jamais présentée, `cancel()` est sans effet.
        let openSession = session
        self.continuation = nil
        self.session = nil
        self.expectedCallback = nil
        continuation.resume(with: result)
        openSession?.cancel()
    }

    /// `true` si l'URL entrante a le même scheme et le même host (insensibles à la casse) et le même
    /// path que le `redirect_uri` envoyé, et porte un paramètre `code` (succès) ou `error` (refus OAuth,
    /// ex. `access_denied` — le login se termine alors proprement avec l'`ApiError` du callback au lieu
    /// de rester bloqué sur la feuille). Comparer le scheme est ce qui permet aux deux canaux hors-bande
    /// (custom scheme via `application(_:open:)`, lien universel via `application(_:continue:)`) de
    /// partager ce même matcher sans faux positif : un login attendu en scheme ne matche que des URL de
    /// ce scheme, un login attendu en https que des liens universels. Le path attendu étant celui qu'on
    /// déclare (AASA pour l'https, redirect_uri pour le scheme), ce matching exact suffit à distinguer
    /// notre callback des autres liens de l'app.
    nonisolated static func isOurCallback(_ url: URL, expectedCallback expected: URL) -> Bool {
        url.scheme?.lowercased() == expected.scheme?.lowercased()
        && url.host?.lowercased() == expected.host?.lowercased()
        && url.path == expected.path
        && (url.queryValue("code") != nil || url.queryValue("error") != nil)
    }

    /// Mappe une erreur d'`ASWebAuthenticationSession` vers une `ReachFiveError`.
    nonisolated static func reachFiveError(for error: Error) -> ReachFiveError {
        guard let sessionError = error as? ASWebAuthenticationSessionError else {
            return .TechnicalError(reason: "Unknown Error \(error.localizedDescription)")
        }
        switch sessionError.code {
        case .canceledLogin:
            return .AuthCanceled
        case .presentationContextNotProvided:
            return .TechnicalError(reason: "Presentation context not provided: \(error.localizedDescription)")
        case .presentationContextInvalid:
            return .TechnicalError(reason: "Presentation context invalid: \(error.localizedDescription)")
        @unknown default:
            return .TechnicalError(reason: "Unknown Error \(error.localizedDescription)")
        }
    }
}
