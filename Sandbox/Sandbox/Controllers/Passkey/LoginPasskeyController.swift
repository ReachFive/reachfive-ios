import Reach5
import UIKit

@available(iOS 16.0, *)
class LoginPasskeyController: UIViewController {
    @IBOutlet var usernameField: UITextField!
    @IBOutlet var usernameLabel: UILabel!
    @IBOutlet var loginButton: UIButton!
    @IBOutlet var createAccountButton: UIButton!

    override func viewWillAppear(_ animated: Bool) {
        usernameField.isHidden = true
        usernameLabel.isHidden = true
        loginButton.isHidden = true
        createAccountButton.isHidden = true

        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("viewDidAppear")

        Task { @MainActor in
            do {
                let request = NativeLoginRequest(presenting: Presentation(from: self), origin: "LoginPasskeyController.viewDidAppear")
                let flow = try await AppDelegate.reachfive().login(withRequest: request, usingModalAuthorizationFor: [.Passkey], display: .IfImmediatelyAvailableCredentials)
                flowTheLogin(flow)
            } catch {
                self.usernameField.isHidden = false
                self.usernameLabel.isHidden = false
                self.loginButton.isHidden = false
                self.createAccountButton.isHidden = false

                switch error {
                case ReachFiveError.AuthCanceled:
                    #if targetEnvironment(macCatalyst)
                        return
                    #else
                        await handleAuthToken {
                            try await AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(presenting: Presentation(from: self), origin: "LoginPasskeyController.viewDidAppear.AuthCanceled"))
                        }
                    #endif
                default:
                    self.presentErrorAlert(title: "Login failed", error)
                }
            }
        }
    }

    @IBAction func nonDiscoverableLogin(_ sender: Any) {
        let request = NativeLoginRequest(presenting: Presentation(from: self), origin: "LoginPasskeyController.nonDiscoverableLogin")

        Task {
            do {
                switch usernameField.text {
                case .none, .some(""):
                    // this is optional, but a good way to present a modal with a fallback to QR code for loging using a nearby device
                    let flow = try await AppDelegate.reachfive().login(withRequest: request, usingModalAuthorizationFor: [.Passkey], display: .Always)
                    flowTheLogin(flow)

                case let .some(username):
                    let authToken = try await AppDelegate.reachfive().login(withNonDiscoverableUsername: .Unspecified(username), forRequest: request, usingModalAuthorizationFor: [.Passkey], display: .Always)
                    goToProfile(authToken)
                }
            } catch ReachFiveError.AuthCanceled {
                #if targetEnvironment(macCatalyst)
                    return
                #else
                    await handleAuthToken {
                        try await AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(presenting: Presentation(from: self), origin: "LoginPasskeyController.nonDiscoverableLogin.AuthCanceled"))
                    }
                #endif
            } catch {
                self.presentErrorAlert(title: "Login failed", error)
            }
        }
    }

    @IBAction func usernameEditingDidBegin(_ sender: Any) {
        print("usernameEditingDidBegin")
        usernameField.backgroundColor = .systemBackground
        usernameField.placeholder = ""
    }

    @IBAction func createAccount(_ sender: Any) {
        guard let username = usernameField.text, !username.isEmpty else {
            print("No username provided")
            usernameField.backgroundColor = .red
            usernameField.placeholder = "enter username"
            return
        }
        let profile = if username.contains("@") {
            ProfilePasskeySignupRequest(email: username)
        } else {
            ProfilePasskeySignupRequest(phoneNumber: username)
        }

        Task {
            await handleAuthToken(errorMessage: "Signup") {
                try await AppDelegate.reachfive().signup(withRequest: PasskeySignupRequest(passkeyProfile: profile, friendlyName: username, presenting: Presentation(from: self), origin: "LoginPasskeyController.createAccount"))
            }
        }
    }

    /// tap anywhere to dismiss the keyboard and access the login and create account buttons
    @IBAction func tappedBackground(_ sender: Any) {
        print("tappedBackground")
        view.endEditing(true)
    }
}
