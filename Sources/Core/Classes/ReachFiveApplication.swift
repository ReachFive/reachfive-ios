import Foundation
import UIKit

public extension ReachFive {
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        interceptUrl(url)
        for provider in providers {
            let _ = provider.application(app, open: url, options: options)
        }
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Task {
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

    @MainActor
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // D'abord les providers (un provider custom peut consommer l'activité)…
        var handled = false
        for provider in providers {
            handled = provider.application(application, continue: userActivity, restorationHandler: restorationHandler) || handled
        }
        if handled { return true }

        // …puis la session web-auth : ne renvoie true QUE si la session en cours attend ce universal
        // link (sinon false, pour que l'app hôte — qui nous forwarde tous ses liens — route elle-même
        // les liens que ReachFive ne gère pas).
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else {
            return false
        }
        return webAuthSession.tryComplete(externalCallbackURL: url)
    }
}
