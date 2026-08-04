import Foundation
import UIKit

public extension ReachFive {
    @MainActor
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        // Out-of-band "custom scheme" channel: an external app reopens the host app through the SDK's
        // scheme. Try the web-auth session first — its matching is exact (scheme + host + path + code/error
        // of the expected redirect_uri, and it is only armed while an out-of-band login is in flight) —
        // otherwise `interceptUrl` would swallow the link as a passwordless callback.
        if webAuthSession.tryComplete(externalCallbackURL: url) {
            return true
        }

        interceptUrl(url)
        withProviders { providers in
            for provider in providers {
                let _ = provider.application(app, open: url, options: options)
            }
        }
        return true
    }

    @MainActor
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        withProviders { providers in
            for provider in providers {
                let _ = provider.application(application, didFinishLaunchingWithOptions: launchOptions)
            }
        }

        return true
    }

    @MainActor
    func applicationDidBecomeActive(_ application: UIApplication) {
        withProviders { providers in
            for provider in providers {
                provider.applicationDidBecomeActive(application)
            }
        }
    }

    @MainActor
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // The web-auth session first: its matching is exact (host + path + code/error of the expected
        // redirect_uri), so there is no risk of it swallowing a link meant for someone else — whereas a
        // custom provider may consume the activity more broadly and hide its callback from the session.
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL,
           webAuthSession.tryComplete(externalCallbackURL: url) {
            return true
        }

        // …then the providers. Returns true ONLY if one of them consumed the activity (false otherwise,
        // so that the host app — which forwards us every link it gets — routes the links ReachFive does
        // not handle itself). When the delivery is deferred, `handled` is still false when we return:
        // we cannot claim to have consumed an activity that no provider has seen yet.
        var handled = false
        withProviders { providers in
            for provider in providers {
                handled = provider.application(application, continue: userActivity, restorationHandler: restorationHandler) || handled
            }
        }
        return handled
    }
}

private extension ReachFive {
    /// Runs `body` over the providers, waiting for them if they do not exist yet.
    ///
    /// The app-lifecycle hooks fire while the app is launching, long before the two round trips of
    /// `initialize()` have created the providers. On a cold start the initialization has not even
    /// *started* when UIKit calls `applicationDidBecomeActive`: the hooks run on the main thread, and
    /// the initialization only gets the main actor once UIKit is done launching the app. Iterating
    /// `providers` right away would walk an empty array and lose the event for good — a missed
    /// `AppEvents.shared.activateApp()` for the Facebook provider, or worse, a universal link or a
    /// custom scheme silently dropped.
    ///
    /// So `body` runs right away when the providers are there, and otherwise as soon as the
    /// initialization has created them — `initialize()` joins the one already in flight rather than
    /// starting a second one. Either way the hook returns immediately: the main thread is never
    /// blocked, and the hooks stay synchronous. Deferred events keep UIKit's order, so a provider is
    /// never handed a link before its own `application(_:didFinishLaunchingWithOptions:)`.
    ///
    /// An event that arrives while the SDK cannot be initialized (offline, for instance) is dropped
    /// rather than kept for later: replaying an activation or a link long after the fact would be
    /// worse than missing it.
    @MainActor
    func withProviders(_ body: @escaping ([Provider]) -> Void) {
        guard case .Initialized = state else {
            let previousDelivery = lifecycleDelivery
            lifecycleDelivery = Task { @MainActor in
                // Deferred events are delivered in the order UIKit sent them: each one waits for the
                // previous one. Left to their own tasks they would resume in any order.
                await previousDelivery?.value
                do {
                    let providers = try await initialize()
                    body(providers)
                } catch {
                    Logger.shared.log("The SDK could not be initialized, so an app lifecycle event was not forwarded to the providers: \(Logger.shared.message(for: error))")
                }
            }
            return
        }

        body(providers)
    }
}
