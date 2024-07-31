import Reach5

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
      AppDelegate.reachfive().addPasswordlessCallback { result in
        switch (result) {
          case .success(authToken):
            // Handle authToken
          case .failure(error):
            // Handle error
          }
      }

      return true
  }
}
