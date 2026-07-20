import Foundation
import UIKit

public protocol ProviderCreator {
    var name: String { get }
    var variant: String? { get }

    /// Factory called by the SDK. Receives the ``ReachFive`` instance, so the creator can reuse
    /// `reachFive.sdkConfig`, `reachFive.reachFiveApi` or high-level helpers such as `buildAuthorizeURL`,
    /// `authWithCode` or `webviewLogin`.
    ///
    /// Do not store `reachFive` strongly in the returned ``Provider``: ReachFive retains its providers,
    /// so a strong back-reference creates a retain cycle. Hold it weakly, or copy the values you need.
    func create(reachFive: ReachFive, providerConfig: ProviderConfig, clientConfigResponse: ClientConfigResponse) -> Provider
}

public protocol Provider {
    var name: String { get }
    func login(scope: [String]?, origin: String, viewController: UIViewController?) async throws -> AuthToken
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    func applicationDidBecomeActive(_ application: UIApplication)
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool
    func logout() async throws
}

/// Default implementations for the app-lifecycle hooks, so a minimal provider only has to implement
/// `name`, `login` and `logout`.
///
/// Note: `logout()` intentionally has NO default. The requirement is `async throws`, while providers
/// usually implement it synchronously (`func logout()`). An `async throws` default would be an
/// *overload* rather than an override, and in an async context Swift would prefer that empty default
/// over a provider's own synchronous `self.logout()` — silently doing nothing.
public extension Provider {
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        false
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {}

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        false
    }
}
