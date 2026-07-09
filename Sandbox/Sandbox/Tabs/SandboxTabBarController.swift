import Foundation
import UIKit
import Reach5

@MainActor
class SandboxTabBarController: UITabBarController {
    // I did not manage to regroup the management of the profile icon in one place
    // there are multiple ways to navigate betweeen the different views and they require different treatment
    // when the profile controller is pushed onto the stack of views programmatically
    // when the user touch the different tabs
    // when the app is relaunched directly in the profile tab...
    // also the notifications are not always available, especially in the profile controller, because the view is not yet loaded
    public static let loggedIn = UIImage(systemName: "person.crop.circle.badge.checkmark")
    public static let loggedOut = UIImage(systemName: "person.crop.circle.badge.xmark")

    public static var tokenExpiredButRefreshable: UIImage? {
        guard #available(iOS 15, *) else {
            return UIImage(systemName: "person.crop.circle.badge.minus")
        }
        return UIImage(systemName: "person.crop.circle.badge.moon")
    }

    public static var tokenPresent: UIImage? {
        guard #available(iOS 14, *) else {
            return UIImage(systemName: "person.crop.circle")
        }
        return UIImage(systemName: "person.crop.circle.badge.questionmark")
    }

    public static var tokenShared: UIImage? {
        return UIImage(systemName: "shared.with.you")
    }

    public static var loggedInButNotFresh: UIImage? {
        guard #available(iOS 15, *) else {
            return UIImage(systemName: "person.crop.circle.badge.plus")
        }
        return UIImage(systemName: "person.crop.circle.badge.clock")
    }

    @IBOutlet weak var sandboxTabBar: UITabBar?

    var clearTokenObserver: NSObjectProtocol?
    var setTokenObserver: NSObjectProtocol?

    override func viewDidLoad() {
        print("SandboxTabBarController.viewDidLoad")
        super.viewDidLoad()

        // Fond opaque : un fond transparent rendait la barre invisible, notamment sur Mac Catalyst
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        if #available(iOS 18.0, *) {
            // Garde la barre d'onglets classique en bas (sur Catalyst/iPad, iOS 18 la déplace sinon en sidebar)
            mode = .tabBar
        }

        clearTokenObserver = NotificationCenter.default.addObserver(forName: .DidClearAuthToken, object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.didLogout()
            }
        }

        setTokenObserver = NotificationCenter.default.addObserver(forName: .DidSetAuthToken, object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.didLogin()
            }
        }

        if #unavailable(iOS 16.0) {
            sandboxTabBar?.items?[0].image = UIImage(systemName: "list.bullet")
        }

        if AppDelegate.storage.getToken() != nil {
            sandboxTabBar?.items?[2].image = SandboxTabBarController.tokenPresent
            sandboxTabBar?.items?[2].selectedImage = SandboxTabBarController.tokenPresent
        }
    }

    func didLogout() {
        print("SandboxTabBarController.didLogout")
        sandboxTabBar?.items?[2].image = SandboxTabBarController.loggedOut
        sandboxTabBar?.items?[2].selectedImage = SandboxTabBarController.loggedOut
    }

    func didLogin() {
        print("SandboxTabBarController.didLogin")
        sandboxTabBar?.items?[2].image = SandboxTabBarController.loggedIn
        sandboxTabBar?.items?[2].selectedImage = SandboxTabBarController.loggedIn
    }
}
