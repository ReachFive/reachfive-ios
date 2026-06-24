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

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Return whether a provider actually consumed the activity, so the host app — which forwards all
        // its universal links here — can still route the ones ReachFive does not handle.
        var handled = false
        for provider in providers {
            handled = provider.application(application, continue: userActivity, restorationHandler: restorationHandler) || handled
        }
        return handled
    }
}
