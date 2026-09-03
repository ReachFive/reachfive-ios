import Foundation
import Reach5

/// The ReachFive environments the Sandbox can talk to, and the one it currently talks to.
///
/// Picking one rebuilds the `ReachFive` instance rather than requiring a rebuild of the app, which is what
/// choosing between configurations used to cost: the environment was decided by `#if targetEnvironment(…)`.
enum SandboxEnvironment: String, CaseIterable {
    case local
    case integQa

    var label: String {
        switch self {
        case .local: "Local"
        case .integQa: "Integ QA"
        }
    }

    var domain: String {
        switch self {
        case .local: "local-sandbox.og4.me"
        case .integQa: "integ-qa-fonctionnelle.reach5.net"
        }
    }

    /// The same client on both environments.
    private static let clientId = "9DKRdQyDLpaJqQQQAR9K"

    /// La reco pour la redirectURI de [https://datatracker.ietf.org/doc/html/rfc8252#section-7.1](RFC 8252) est:
    /// - apps MUST use a URI scheme based on a domain name under their control, expressed in reverse order, as recommended by Section 3.8 of [RFC7595] for private-use URI schemes
    /// - Following the requirements of Section 3.2 of [RFC3986], as there is no naming authority for private-use URI scheme redirects, only a single slash ("/") appears after the scheme component.
    ///
    /// A complete example of a redirect URI utilizing a private-use URI scheme is:
    ///
    ///     com.example.app:/oauth2redirect/example-provider
    var sdkConfig: SdkConfig {
        SdkConfig(domain: domain, clientId: Self.clientId)
    }

    // MARK: - Selection

    private static let defaultsKey = "sandboxEnvironment"

    /// Defaults to what the `#if` used to pick, so an app that never visits the settings behaves as before.
    private static var fallback: SandboxEnvironment {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
            .local
        #else
            .integQa
        #endif
    }

    static var selected: SandboxEnvironment {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(SandboxEnvironment.init(rawValue:)) ?? fallback
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// What the app was built with, for the settings screen to show — the first thing to ask for when a report
/// comes in, and the first thing nobody can answer from a screenshot.
enum SandboxVersions {
    /// The satellites are referenced as local packages, so they have no version of their own to report:
    /// whether they are linked at all is the only thing worth showing.
    struct Component {
        let name: String
        let detail: String
    }

    static var all: [Component] {
        [
            Component(name: "Reach5", detail: SdkVersion.current),
            Component(name: "Reach5Google", detail: linked(google)),
            Component(name: "Reach5Facebook", detail: linked(facebook)),
        ]
    }

    private static func linked(_ isLinked: Bool) -> String {
        isLinked ? "linked (local package, no version)" : "not linked"
    }

    private static var google: Bool {
        #if canImport(Reach5Google)
            true
        #else
            false
        #endif
    }

    private static var facebook: Bool {
        #if canImport(Reach5Facebook)
            true
        #else
            false
        #endif
    }
}
