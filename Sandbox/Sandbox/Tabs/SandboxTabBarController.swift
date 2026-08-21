import Foundation
import Reach5
import UIKit

@MainActor
class SandboxTabBarController: UITabBarController {
    // I did not manage to regroup the management of the profile icon in one place
    // there are multiple ways to navigate betweeen the different views and they require different treatment
    // when the profile controller is pushed onto the stack of views programmatically
    // when the user touch the different tabs
    // when the app is relaunched directly in the profile tab...
    // also the notifications are not always available, especially in the profile controller, because the view is not yet loaded
    static let loggedIn = UIImage(systemName: "person.crop.circle.badge.checkmark")
    static let loggedOut = UIImage(systemName: "person.crop.circle.badge.xmark")

    static var tokenExpiredButRefreshable: UIImage? {
        guard #available(iOS 15, *) else {
            return UIImage(systemName: "person.crop.circle.badge.minus")
        }
        return UIImage(systemName: "person.crop.circle.badge.moon")
    }

    static var tokenPresent: UIImage? {
        guard #available(iOS 14, *) else {
            return UIImage(systemName: "person.crop.circle")
        }
        return UIImage(systemName: "person.crop.circle.badge.questionmark")
    }

    static var tokenShared: UIImage? {
        UIImage(systemName: "shared.with.you")
    }

    static var loggedInButNotFresh: UIImage? {
        guard #available(iOS 15, *) else {
            return UIImage(systemName: "person.crop.circle.badge.plus")
        }
        return UIImage(systemName: "person.crop.circle.badge.clock")
    }

    @IBOutlet var sandboxTabBar: UITabBar?

    var clearTokenObserver: NSObjectProtocol?
    var setTokenObserver: NSObjectProtocol?

    override func viewDidLoad() {
        print("SandboxTabBarController.viewDidLoad")
        super.viewDidLoad()
        delegate = self

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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.title = selectedViewController?.title
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

extension SandboxTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        navigationItem.title = viewController.title
    }
}
