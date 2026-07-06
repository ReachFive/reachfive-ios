import AuthenticationServices

/// Porte le login web en cours : démarre une `ASWebAuthenticationSession`, attend son callback,
///  et —pour les providers à universal link — laisse un lien reçu hors-bande via `application(_:continue:)`
/// le compléter (``tryComplete(externalCallbackURL:)``).
///
/// **Un seul login à la fois.** La feuille modale d'une `ASWebAuthenticationSession` empêche d'en
/// lancer un second sur iPhone, mais un second `start(...)` reste atteignable (logout web pendant un
/// login, nouveau login après un aller-retour `externalApp` abandonné, iPad multi-fenêtres) : le
/// dernier arrivé gagne — le login précédent est repris avec `.AuthCanceled` et sa feuille est fermée.
///
/// Les callbacks tardifs ou dupliqués sont neutralisés de deux façons : un **jeton par tentative**
/// (`attempt`) — pour qu'un callback d'une `ASWebAuthenticationSession` périmée ne puisse jamais
/// reprendre la continuation d'un login plus récent — et la remise à `nil` de `continuation` dans
/// `complete(_:)` — pour que la résolution gagnante (in-band, hors-bande, ou annulation) reprenne la
/// continuation exactement une fois.
///
/// `@MainActor` : tout le domaine `ASWebAuthenticationSession` est déjà main-thread.
@MainActor
final class WebAuthenticationSession {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    /// Le `redirect_uri` parsé attendu pour cette tentative ; `nil` hors d'un login → `tryComplete` ne matche rien.
    private var expectedCallback: URL?
    /// Identifie la tentative en cours ; un callback capturant un `attempt` périmé est ignoré.
    private var attempt = 0
    private let baseScheme: String

    nonisolated init(baseScheme: String) {
        self.baseScheme = baseScheme
    }

    /// Démarre un login web et attend son callback (succès, erreur ou annulation). Le ``WebSessionMode``
    /// décrit comment la session se termine (scheme in-band, universal link in-band, ou app externe
    /// hors-bande) et pilote donc à la fois la construction de la session et le canal du callback.
    func start(url: URL,
               mode: WebSessionMode,
               presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
               prefersEphemeralWebBrowserSession: Bool = false) async throws -> URL {

        return try await withCheckedThrowingContinuation { continuation in
            cancelPendingAttempt()
            attempt += 1
            let attempt = attempt
            self.continuation = continuation
            // Seul le mode hors-bande arme `tryComplete` ; en in-band, la session se complète elle-même.
            self.expectedCallback = mode.outOfBandCallback

            let completionHandler: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
                // Tout passe sur le main thread pour éviter les situations de compétition.
                Task { @MainActor in
                    self?.handleSessionCompletion(attempt: attempt, callbackURL: callbackURL, error: error)
                }
            }

            let session: ASWebAuthenticationSession
            switch mode {
            case .sdkScheme:
                // Scheme custom intercepté par la session (historique, tout iOS).
                session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: baseScheme,
                    completionHandler: completionHandler)

            case let .universalLink(callback):
                // iOS 17.4+ : universal link intercepté in-band dans la webview via `callback: .https`
                // (nécessite l'Associated Domain `webcredentials:<host>`). `@available` est impossible
                // sur un case d'enum porteur de valeur, on teste donc la disponibilité ici, à l'usage.
                guard #available(iOS 17.4, *), let host = callback.host else {
                    complete(attempt: attempt, .failure(.TechnicalError(reason: "In-sheet universal link callback requires iOS 17.4+ and a host: \(callback)")))
                    return
                }
                session = ASWebAuthenticationSession(
                    url: url,
                    callback: .https(host: host, path: callback.path),
                    completionHandler: completionHandler)

            case .externalApp:
                // Le flow se termine dans une app externe : la session ne recevra jamais le callback
                // (traité hors-bande par `tryComplete`), on ne lui donne donc aucun scheme à intercepter.
                session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: nil,
                    completionHandler: completionHandler)
            }

            // Fenêtre qui sert d'ancre de présentation à la session.
            session.presentationContextProvider = presentationContextProvider
            session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
            self.session = session

            // Démarre le flow d'authentification.
            if !session.start() {
                // Log the error for debugging purposes.
                #if DEBUG
                print("WebAuthentication session failed to start.")
                #endif
                // Si start() renvoie false, le completion handler peut ne jamais être appelé : on
                // reprend la continuation avec une erreur.
                complete(attempt: attempt, .failure(ReachFiveError.TechnicalError(reason: "ASWebAuthenticationSession failed to start")))
            }
        }
    }

    /// Complète le login en cours si l'URL entrante est bien notre callback, et annule la session
    /// encore ouverte. Renvoie `true` seulement dans ce cas — sinon `false`, pour que l'app hôte puisse
    /// router elle-même le lien.
    func tryComplete(externalCallbackURL url: URL) -> Bool {
        guard let expectedCallback,
              Self.isOurCallback(url, expectedCallback: expectedCallback) else {
            return false
        }
        // Capture `session` avant `complete(_:)`, qui le met à nil ; on en a besoin pour annuler la
        // session encore ouverte. Annuler après reprise est sans effet (le callback d'annulation
        // trouve une `continuation` déjà nil et est ignoré).
        let runningSession = session
        complete(attempt: attempt, .success(url))
        runningSession?.cancel()
        return true
    }

    /// Reprend le login encore en attente avec `.AuthCanceled` et ferme sa feuille — sans effet s'il
    /// n'y en a pas. Appelé quand un nouveau `start(...)` le remplace (dernier arrivé gagne), pour ne
    /// jamais laisser une continuation geler sans résolution.
    private func cancelPendingAttempt() {
        guard continuation != nil else { return }
        // Même capture de `session` avant `complete(_:)` que dans `tryComplete`.
        let staleSession = session
        complete(attempt: attempt, .failure(.AuthCanceled))
        staleSession?.cancel()
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

    private func complete(attempt: Int, _ result: Result<URL, ReachFiveError>) {
        // Ignore un callback périmé (login plus récent) ou une seconde résolution (`continuation` déjà nil).
        guard attempt == self.attempt, let continuation else { return }
        self.continuation = nil
        self.session = nil
        self.expectedCallback = nil
        continuation.resume(with: result)
    }

    /// `true` si l'URL entrante a le même host (insensible à la casse) et le même path que le
    /// `redirect_uri` envoyé, et porte un paramètre `code`. Le path attendu étant celui qu'on déclare
    /// dans l'AASA, ce matching exact suffit à distinguer notre callback des autres liens de l'app.
    nonisolated static func isOurCallback(_ url: URL, expectedCallback expected: URL) -> Bool {
        url.host?.lowercased() == expected.host?.lowercased()
        && url.path == expected.path
        && url.queryValue("code") != nil
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
