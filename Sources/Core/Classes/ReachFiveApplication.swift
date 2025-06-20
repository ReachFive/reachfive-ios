import Foundation
import UIKit

public extension ReachFive {
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        Task {
            await interceptUrl(url)
        }
        for provider in providers {
            let _ = provider.application(app, open: url, options: options)
        }
        return true
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Task {
            await initialize().map { providers in
                for provider in providers {
                    let _ = provider.application(application, didFinishLaunchingWithOptions: launchOptions)
                }
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
        for provider in providers {
            let _ = provider.application(application, continue: userActivity, restorationHandler: restorationHandler)
        }
        return true
    }
}
