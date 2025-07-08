import Foundation
import UIKit
import Reach5
import AuthenticationServices

class ActionController: UITableViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        Task { @MainActor in
            tableView.deselectRow(at: indexPath, animated: true)

            guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }

            // Section Native
            if indexPath.section == 1 {
                // Sign in with Apple
                if indexPath.row == 1 {
                    let request = NativeLoginRequest(anchor: window, origin: "ActionController: Section Native")
                    await handleLoginFlow {
                        try await AppDelegate.reachfive().login(withRequest: request, usingModalAuthorizationFor: [.SignInWithApple], display: .Always)
                    }
                }
            }

            // Section Passkey
            if #available(iOS 16.0, *), indexPath.section == 2 {
                let loginRequest = NativeLoginRequest(anchor: window, origin: "ActionController: Section Passkey")

                do {
                    // Login with passkey: modal persistent
                    if indexPath.row == 1 {
                        let flow = try await AppDelegate.reachfive().login(withRequest: loginRequest, usingModalAuthorizationFor: [.Passkey], display: .Always)
                        flowTheLogin(flow)
                    } else
                    // Login with passkey: modal non-persistent
                    if indexPath.row == 2 {
                        let flow = try await AppDelegate.reachfive().login(withRequest: loginRequest, usingModalAuthorizationFor: [.Passkey], display: .IfImmediatelyAvailableCredentials)
                        flowTheLogin(flow)
                    }
                } catch {
                    // Do not show error, the goal is to be non invasive in the UI
                }
            }

            // Section Webview
            if indexPath.section == 3 {
                // standard webview
                if indexPath.row == 0 {
                    await handleAuthToken {
                        try await AppDelegate.reachfive().webviewLogin(WebviewLoginRequest(presentationContextProvider: self, origin: "ActionController.webviewLogin"))
                    }
                }
            }

            // Section Others
            if indexPath.section == 4 {
                // Login with refresh
                if indexPath.row == 2 {
                    guard let token = AppDelegate.storage.getToken() else {
                        return
                    }
                    do {
                        let authToken = try await AppDelegate.reachfive().refreshAccessToken(authToken: token)
                        goToProfile(authToken)
                    } catch {
                        print("refresh error \(error)")
                        AppDelegate.storage.removeToken()
                    }
                }
            }
        }
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        // passkey section restricted to iOS >= 16
        //TODO voir si on peut à la place carrément ne pas afficher la section
        if indexPath.section == 2, #unavailable(iOS 16.0) {
            presentAlert(title: "Login", message: "Passkey requires iOS 16")
            return nil
        }
        #if targetEnvironment(macCatalyst)
        if indexPath.section == 2, indexPath.row == 3 {
            presentAlert(title: "Login", message: "AutoFill not available on macOS")
            return nil
        }
        #endif
        return indexPath
    }
}

extension ActionController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}
