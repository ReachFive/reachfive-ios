import Foundation
import UIKit
import AuthenticationServices
import Reach5

// MARK: - Doc-example compilation harness
//
// The .adoc pages include the snippets in docs/modules/ROOT/examples/*.swift.
// Those snippets are *fragments*: they assume an ambient application context
// (an `AppDelegate.reachfive()` accessor, a few view-controller helpers) and
// they sometimes contain `= // paste here` placeholders.
//
// This file provides that ambient context as compile-only stubs so the SDK
// API calls inside each snippet can be type-checked against the real `Reach5`
// module. Nothing here is ever executed — `__placeholder()` traps at runtime.
// If a snippet calls an API that no longer exists or changed signature, the
// build of the DocExamples target fails.

/// A value of any statically-known type, for `let x: T = // paste…` placeholders.
func __placeholder<T>() -> T { fatalError("doc placeholder – never executed") }

/// The accessor every snippet assumes. A real app defines this on its own
/// AppDelegate; here it is a stub returning a (never-created) ReachFive.
enum AppDelegate {
    static func reachfive() -> ReachFive { __placeholder() }
    static func createAlert(title: String, message: String) -> UIAlertController { __placeholder() }
}

/// App-side navigation helper referenced by some snippets.
func goToProfile(_ authToken: AuthToken) {}

// MARK: - Ambient values the snippets assume from prose or a previous snippet.
// Providing them with their real API-expected type lets the *API call* be
// type-checked without the "cannot find 'x' in scope" noise.
let profileAuthToken: AuthToken = __placeholder()
let freshProfileAuthToken: AuthToken = __placeholder()
let authToken: AuthToken = __placeholder()
let window: ASPresentationAnchor = __placeholder()
let profile: ProfilePasskeySignupRequest = __placeholder()
let verificationCode: String = __placeholder()
let verificationCodeInput: String = __placeholder()
let friendlyName: String = __placeholder()
let email: String = __placeholder()
let emailInput: String = __placeholder()
let username: String = __placeholder()
let phoneNumberInput: String = __placeholder()
let deviceId: String = __placeholder()
let id: String = __placeholder()
let DOMAIN: String = __placeholder()
let CLIENT_ID: String = __placeholder()

// MARK: - Scaffolding referenced by the custom-provider examples.
// These stand for types the reader supplies (a native SDK to wrap) or defines
// in a companion snippet, so the *SDK-facing* calls around them can be checked.

/// Stands for the reader's own native SDK, wrapped by a custom provider.
class MyNativeSDK {
    static let shared = MyNativeSDK()
    func login(presenting: UIViewController) async throws -> String { __placeholder() }
    func logout() {}
}

/// The custom ProviderCreator defined in customProviderWrappingNativeSDK and
/// reused in registerCustomProvider (which lives on another doc page).
class MyProvider: ProviderCreator {
    var name: String = "my-provider"
    var variant: String?
    init(variant: String? = nil) { self.variant = variant }
    func create(reachFive: ReachFive, providerConfig: ProviderConfig, clientConfigResponse: ClientConfigResponse) -> Provider {
        __placeholder()
    }
}

/// Base class for the imperative snippets. Many of them use `self` as a
/// presentation context (`viewController: self`, `presentationContextProvider:
/// self`), so the wrapper must be a UIViewController that conforms to the
/// authentication presentation protocol.
class DocExampleContext: UIViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        __placeholder()
    }
}
