import AuthenticationServices

/// Abstraction de la session web sous-jacente. Découple le store de `ASWebAuthenticationSession`
/// (non mockable) et rend le routage testable. Conformé par `WebAuthenticationSession`.
@MainActor
protocol WebAuthRunning: AnyObject {
    func start(url: URL,
               routing: WebAuthRouting,
               callbackURLScheme: String,
               presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
               prefersEphemeralWebBrowserSession: Bool) async throws -> URL
    func complete(externalCallbackURL url: URL)
}

extension WebAuthenticationSession: WebAuthRunning {}

/// Gestionnaire centralisé des sessions de login web en cours, porté par ``ReachFive``.
///
/// Il les indexe par leur `state` (clé de corrélation) afin, quand un universal link arrive hors-bande
/// via `application(_:continue:)`, de reconnaître s'il s'agit d'un de nos callbacks et, le cas échéant,
/// de compléter la session correspondante.
///
/// `@MainActor` : tout le domaine `ASWebAuthenticationSession` est déjà
/// main-thread, donc l'isolation main suffit à éliminer les data races, sans hop async.
@MainActor
final class WebAuthSessionStore {
    private struct Entry {
        let routing: WebAuthRouting
        let session: WebAuthRunning
    }

    private var entries: [String: Entry] = [:]
    // `nonisolated(unsafe)` : `let` immuable fixé à l'init et lu uniquement sur le main actor (depuis
    // `run`). Permet l'init `nonisolated` (ReachFive est non isolé) sans risque de course.
    nonisolated(unsafe) private let makeSession: () -> WebAuthRunning

    nonisolated init(makeSession: @escaping () -> WebAuthRunning = { WebAuthenticationSession() }) {
        self.makeSession = makeSession
    }

    /// Démarre un login web et attend son callback. Crée une session fraîche (à usage unique),
    /// l'enregistre sous `routing.state` le temps du flow, et la retire à la fin (succès, erreur, annulation).
    func run(routing: WebAuthRouting,
             url: URL,
             callbackURLScheme: String,
             presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
             prefersEphemeralWebBrowserSession: Bool) async throws -> URL {
        let session = makeSession()
        entries[routing.state] = Entry(routing: routing, session: session)
        defer { entries[routing.state] = nil }
        return try await session.start(
            url: url,
            routing: routing,
            callbackURLScheme: callbackURLScheme,
            presentationContextProvider: presentationContextProvider,
            prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession)
    }

    /// Complète hors-bande la session que ce universal link concerne (reçu via
    /// `application(_:continue:)`). Renvoie `true` seulement si une session active a matché — sinon
    /// `false`, pour que l'app hôte puisse router elle-même le lien.
    func complete(externalCallbackURL url: URL) -> Bool {
        guard let entry = entries.values.first(where: { $0.routing.matches(url) }) else {
            return false
        }
        entry.session.complete(externalCallbackURL: url)
        return true
    }
}
