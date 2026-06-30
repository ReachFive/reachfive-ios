import AuthenticationServices

/// Porte le login web en cours : démarre une `ASWebAuthenticationSession`, attend son callback, et —
/// pour les providers à universal link — laisse un lien reçu hors-bande via `application(_:continue:)`
/// le compléter (``tryComplete(externalCallbackURL:)``).
///
/// **Un seul login à la fois.** La feuille modale d'une `ASWebAuthenticationSession` empêche d'en
/// lancer un second sur iPhone. Le cas multi-fenêtres (iPad/macCatalyst) n'est pas couvert : un second
/// `start(...)` écrase l'état en cours et le login précédent ne peut alors plus être complété.
///
/// Les callbacks tardifs ou dupliqués sont neutralisés de deux façons : un **jeton par tentative**
/// (`attempt`) — pour qu'un callback d'une `ASWebAuthenticationSession` périmée ne puisse jamais
/// reprendre la continuation d'un login plus récent — et un garde **une-seule-fois** (`hasResumed`) —
/// pour que la résolution gagnante (in-band, hors-bande, ou annulation) reprenne la continuation
/// exactement une fois.
///
/// `@MainActor` : tout le domaine `ASWebAuthenticationSession` est déjà main-thread.
@MainActor
final class WebAuthenticationSession {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    /// Le `redirect_uri` parsé attendu pour cette tentative ; `nil` hors d'un login → `tryComplete`
    /// ne matche rien.
    private var expectedCallback: URL?
    private var hasResumed = false
    /// Identifie la tentative en cours ; un callback capturant un `attempt` périmé est ignoré.
    private var attempt = 0

    nonisolated init() {}

    /// Démarre un login web et attend son callback (succès, erreur ou annulation).
    func start(url: URL,
               expectedCallback: URL?,
               callbackURLScheme: String,
               presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
               prefersEphemeralWebBrowserSession: Bool = false) async throws -> URL {

        return try await withCheckedThrowingContinuation { continuation in
            attempt += 1
            let attempt = attempt
            self.continuation = continuation
            self.expectedCallback = expectedCallback
            self.hasResumed = false

            let completionHandler: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
                // Tout passe sur le main thread pour éviter les races.
                Task { @MainActor in
                    self?.handleSessionCompletion(attempt: attempt, callbackURL: callbackURL, error: error)
                }
            }

            let session: ASWebAuthenticationSession
            // iOS 17.4+ : quand le redirect_uri est un universal link (https), on intercepte la
            // redirection in-band directement dans la session via le callback `.https` (nécessite
            // l'Associated Domain `webcredentials:<host>`). Sinon, scheme custom (legacy, iOS < 17.4).
            if #available(iOS 17.4, *),
               let expectedCallback,
               expectedCallback.scheme == "https",
               let host = expectedCallback.host {
                session = ASWebAuthenticationSession(
                    url: url,
                    callback: .https(host: host, path: expectedCallback.path),
                    completionHandler: completionHandler)
            } else {
                session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackURLScheme,
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
        // session encore ouverte. Annuler après reprise est sans effet (le callback d'annulation est
        // ignoré grâce au garde `hasResumed`).
        let runningSession = session
        complete(attempt: attempt, .success(url))
        runningSession?.cancel()
        return true
    }

    private func handleSessionCompletion(attempt: Int, callbackURL: URL?, error: Error?) {
        if let error {
            complete(attempt: attempt, .failure(Self.reachFiveError(for: error)))
        } else if let callbackURL {
            complete(attempt: attempt, .success(callbackURL))
        } else {
            complete(attempt: attempt, .failure(ReachFiveError.TechnicalError(reason: "No callback URL")))
        }
    }

    private func complete(attempt: Int, _ result: Result<URL, Error>) {
        // Ignore un callback périmé (login plus récent) ou une seconde résolution.
        guard attempt == self.attempt, !hasResumed, let continuation else { return }
        hasResumed = true
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
        switch error._code {
        case 1: .AuthCanceled
        case 2: .TechnicalError(reason: "Presentation context not provided: \(error.localizedDescription)")
        case 3: .TechnicalError(reason: "Presentation context invalid: \(error.localizedDescription)")
        default: .TechnicalError(reason: "Unknown Error \(error.localizedDescription)")
        }
    }
}
