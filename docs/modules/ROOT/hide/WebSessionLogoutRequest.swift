// Web-based logout from a view controller
import UIKit
import ReachFive

class MyViewController: UIViewController, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return self.view.window!
    }
    
    func logoutUser() async {
        let webLogoutRequest = WebSessionLogoutRequest(
            presentationContextProvider: self // Use current view controller
        )
        do {
            try await AppDelegate.reachfive().logout(webSessionLogout: webLogoutRequest)
            print("Web logout successful, browser cookies cleared")
        } catch {
            print("Logout failed: \(error)")
        }
    }
}

// Web-based logout with origin
let webLogoutRequest = WebSessionLogoutRequest(
    presentationContextProvider: self, // Use current view controller
    origin: "app_logout"
)
do {
    try await AppDelegate.reachfive().logout(webSessionLogout: webLogoutRequest)
    print("Web logout successful, browser cookies cleared")
} catch {
    print("Logout failed: \(error)")
}