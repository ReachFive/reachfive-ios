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
                    try await AppDelegate.reachfive()
                        .login(withRequest: NativeLoginRequest(anchor: window, origin: "ActionController: Section Native"), usingModalAuthorizationFor: [.SignInWithApple], display: .Always)
                        .onSuccess(callback: handleLoginFlow)
                        .onFailure { error in
                            let alert = AppDelegate.createAlert(title: "Login failed", message: "Error: \(error.localizedDescription)")
                            self.present(alert, animated: true)
                        }
                }
            }

            let loginRequest = NativeLoginRequest(anchor: window, origin: "ActionController: Section Passkey")

            // Section Passkey
            if #available(iOS 16.0, *), indexPath.section == 2 {
                // Login with passkey: modal persistent
                if indexPath.row == 1 {
                    try await AppDelegate.reachfive()
                        .login(withRequest: loginRequest, usingModalAuthorizationFor: [.Passkey], display: .Always)
                        .onSuccess(callback: handleLoginFlow)
                } else
                // Login with passkey: modal non-persistent
                if indexPath.row == 2 {
                    try await AppDelegate.reachfive()
                        .login(withRequest: loginRequest, usingModalAuthorizationFor: [.Passkey], display: .IfImmediatelyAvailableCredentials)
                        .onSuccess(callback: handleLoginFlow)
                }
            }

            // Section Webview
            if indexPath.section == 3 {
                // standard webview
                if indexPath.row == 0 {
                    try await AppDelegate.reachfive()
                        .webviewLogin(WebviewLoginRequest(presentationContextProvider: self, origin: "ActionController.webviewLogin"))
                        .onComplete { self.handleResult(result: $0) }
                }
            }

            // Section Others
            if indexPath.section == 4 {
                // Login with refresh
                if indexPath.row == 2 {
                    guard let token = AppDelegate.storage.getToken() else {
                        return
                    }
                    try await AppDelegate.reachfive()
                        .refreshAccessToken(authToken: token)
                        .onSuccess(callback: goToProfile)
                        .onFailure { error in
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
            let alert = AppDelegate.createAlert(title: "Login", message: "Passkey requires iOS 16")
            present(alert, animated: true)
            return nil
        }
        #if targetEnvironment(macCatalyst)
        if indexPath.section == 2, indexPath.row == 3 {
            let alert = AppDelegate.createAlert(title: "Login", message: "AutoFill not available on macOS")
            present(alert, animated: true)
            return nil
        }
        #endif
        return indexPath
    }

    func handleResult(result: Result<AuthToken, ReachFiveError>) {
        switch result {
        case .success(let authToken):
            goToProfile(authToken)
        case .failure(let error):
            let alert = AppDelegate.createAlert(title: "Login failed", message: "Error: \(error.localizedDescription)")
            present(alert, animated: true)
        }
    }
}

extension ActionController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}
