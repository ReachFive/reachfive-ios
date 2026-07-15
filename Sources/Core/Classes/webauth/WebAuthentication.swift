import AuthenticationServices

/// Porte le login web en cours : démarre une `ASWebAuthenticationSession` et attend son callback.
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
/// `complete(_:)` — pour que la résolution gagnante (callback ou annulation) reprenne la
/// continuation exactement une fois.
///
/// `@MainActor` : tout le domaine `ASWebAuthenticationSession` est déjà main-thread.
@MainActor
final class WebAuthenticationSession {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    /// Identifie la tentative en cours ; un callback capturant un `attempt` périmé est ignoré.
    private var attempt = 0
    private let baseScheme: String

    nonisolated init(baseScheme: String) {
        self.baseScheme = baseScheme
    }

    /// Démarre un login web sur le scheme custom du SDK et attend son callback (succès, erreur ou
    /// annulation). Si le `Task` appelant est annulé (vue démontée, timeout…), la feuille est fermée
    /// et l'appel se termine par `.AuthCanceled`.
    func start(url: URL,
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

                let completionHandler: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
                    // Tout passe sur le main thread pour éviter les situations de compétition.
                    Task { @MainActor in
                        self?.handleSessionCompletion(attempt: attempt, callbackURL: callbackURL, error: error)
                    }
                }

                // Scheme custom intercepté par la session (historique, tout iOS).
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: self.baseScheme,
                    completionHandler: completionHandler)

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
    /// la feuille si elle est encore présentée (annulation, remplacement).
    private func complete(attempt: Int, _ result: Result<URL, ReachFiveError>) {
        // Ignore un callback périmé (login plus récent) ou une seconde résolution (`continuation` déjà nil).
        guard attempt == self.attempt, let continuation else { return }
        // Capture la session avant de la nil-er pour fermer sa feuille après la reprise. Le callback
        // d'annulation tardif qui en résulte est ignoré (continuation désormais nil) ; sur une session
        // déjà terminée ou jamais présentée, `cancel()` est sans effet.
        let openSession = session
        self.continuation = nil
        self.session = nil
        continuation.resume(with: result)
        openSession?.cancel()
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
