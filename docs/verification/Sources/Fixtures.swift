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

/// Base class for the imperative snippets. Many of them use `self` as a
/// presentation context (`viewController: self`, `presentationContextProvider:
/// self`), so the wrapper must be a UIViewController that conforms to the
/// authentication presentation protocol.
class DocExampleContext: UIViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        __placeholder()
    }
}
