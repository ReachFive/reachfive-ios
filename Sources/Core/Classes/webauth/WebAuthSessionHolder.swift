import AuthenticationServices

/// Porte la session de login web en cours, le temps de son flow, pour qu'un universal link reçu
/// hors-bande via `application(_:continue:)` puisse la compléter.
///
/// **Fente unique** : on suppose au plus un login web à la fois — la feuille modale d'une
/// `ASWebAuthenticationSession` empêche d'en lancer un second. Le cas multi-fenêtres (iPad/macCatalyst)
/// n'est pas couvert : un second login écraserait la fente, et la session précédente ne pourrait alors
/// plus être complétée hors-bande.
///
/// `@MainActor` : tout le domaine `ASWebAuthenticationSession` est déjà main-thread.
@MainActor
final class WebAuthSessionHolder {
    private struct Current {
        let session: WebAuthenticationSession
        let expectedCallback: URL?
    }

    private var current: Current?

    nonisolated init() {}

    /// Démarre un login web et attend son callback. La session est posée dans la fente le temps du flow
    /// et retirée à la fin (succès, erreur, annulation).
    func run(url: URL,
             expectedCallback: URL?,
             callbackURLScheme: String,
             presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
             prefersEphemeralWebBrowserSession: Bool) async throws -> URL {
        let session = WebAuthenticationSession()
        current = Current(session: session, expectedCallback: expectedCallback)
        // On ne vide la fente que si elle pointe ENCORE notre session : évite qu'un flow tardif n'efface
        // la fente d'un login démarré entre-temps.
        defer { if current?.session === session { current = nil } }
        return try await session.start(
            url: url,
            expectedCallback: expectedCallback,
            callbackURLScheme: callbackURLScheme,
            presentationContextProvider: presentationContextProvider,
            prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession)
    }

    /// Complète la session en cours si l'URL entrante est bien notre callback. Renvoie `true` seulement
    /// dans ce cas — sinon `false`, pour que l'app hôte puisse router elle-même le lien.
    func tryComplete(externalCallbackURL url: URL) -> Bool {
        guard let current,
              let expected = current.expectedCallback,
              Self.isOurCallback(url, expectedCallback: expected) else {
            return false
        }
        current.session.complete(externalCallbackURL: url)
        return true
    }

    /// `true` si l'URL entrante a le même host (insensible à la casse) et le même path que le
    /// `redirect_uri` envoyé, et porte un paramètre `code`. Le path attendu étant celui qu'on déclare
    /// dans l'AASA, ce matching exact suffit à distinguer notre callback des autres liens de l'app.
    nonisolated static func isOurCallback(_ url: URL, expectedCallback expected: URL) -> Bool {
        url.host?.lowercased() == expected.host?.lowercased()
            && url.path == expected.path
            && url.queryValue("code") != nil
    }
}
