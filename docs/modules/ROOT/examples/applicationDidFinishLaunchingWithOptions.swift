import Reach5

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return AppDelegate.reachfive().application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
