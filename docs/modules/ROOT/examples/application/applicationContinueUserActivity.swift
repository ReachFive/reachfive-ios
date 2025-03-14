import Reach5
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return AppDelegate.reachfive().application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}
