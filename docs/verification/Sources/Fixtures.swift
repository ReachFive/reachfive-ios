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

/// Base class for the imperative snippets. Many of them use `self` as a
/// presentation context (`viewController: self`, `presentationContextProvider:
/// self`), so the wrapper must be a UIViewController that conforms to the
/// authentication presentation protocol.
class DocExampleContext: UIViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        __placeholder()
    }
}
