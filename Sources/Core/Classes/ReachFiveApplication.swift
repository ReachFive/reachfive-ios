import Foundation
import UIKit

public extension ReachFive {
    @MainActor
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        // Out-of-band "custom scheme" channel: a third-party app reopens the host app through the SDK's
        // scheme. The web-auth session is tried first — its matching is exact (scheme + host + path +
        // code/error of the expected redirect_uri) — otherwise `routeUrl` would swallow the link as a passwordless callback.
        if webAuthSession.tryComplete(externalCallbackURL: url) {
            return true
        }

        // Returns true only if the URL was consumed (same contract as `application(_:continue:)`): a host
        // app that forwards all of its links to us must be able to route the ones that aren't ours. That is
        // why `routeUrl` does not fall back to `interceptPasswordless`, unlike `interceptUrl` called
        // directly.
        var handled = routeUrl(url)
        for provider in providers {
            handled = provider.application(app, open: url, options: options) || handled
        }
        return handled
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // On the main actor: the hook we forward is a UIKit app-lifecycle callback, and the native
        // SDKs behind the providers expect it on the main thread — as UIKit called us here.
        Task { @MainActor in
            do {
                for provider in try await initialize() {
                    let _ = provider.application(application, didFinishLaunchingWithOptions: launchOptions)
                }
            } catch {
                //TODO: faire une passe de cohérence sur l'utilisation de #if DEBUG et du Logger
                #if DEBUG
                print(Logger.shared.message(for: error))
                #endif
            }
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        for provider in providers {
            provider.applicationDidBecomeActive(application)
        }
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Returns true only if a provider consumed the activity (false otherwise, so the host app — which
        // forwards all of its links to us — routes the ones ReachFive does not handle).
        var handled = false
        for provider in providers {
            handled = provider.application(application, continue: userActivity, restorationHandler: restorationHandler) || handled
        }
        return handled
    }
}
