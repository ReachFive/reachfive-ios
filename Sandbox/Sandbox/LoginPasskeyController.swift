import UIKit
import Reach5


@available(iOS 16.0, *)
class LoginPasskeyController: UIViewController {

    @IBOutlet weak var usernameField: UITextField!
    @IBOutlet weak var usernameLabel: UILabel!
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var createAccountButton: UIButton!

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

        guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
        Task { @MainActor in
            try await AppDelegate.reachfive().login(withRequest: NativeLoginRequest(anchor: window, origin: "LoginPasskeyController.viewDidAppear"), usingModalAuthorizationFor: [.Passkey], display: .IfImmediatelyAvailableCredentials)
                .onSuccess(callback: handleLoginFlow)
                .onFailure { error in

                    self.usernameField.isHidden = false
                    self.usernameLabel.isHidden = false
                    self.loginButton.isHidden = false
                    self.createAccountButton.isHidden = false

                    switch error {
                    case ReachFiveError.AuthCanceled:
                    #if targetEnvironment(macCatalyst)
                        return
                    #else
                        try await AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(anchor: window, origin: "LoginPasskeyController.viewDidAppear.AuthCanceled"))
                            .onSuccess(callback: self.goToProfile)
                            .onFailure { error in
                                let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.localizedDescription)")
                                self.present(alert, animated: true)
                            }
                    #endif
                    default:
                        let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.localizedDescription)")
                        self.present(alert, animated: true)
                    }
                }
        }
    }

    @IBAction func nonDiscoverableLogin(_ sender: Any) {
        guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
        let request = NativeLoginRequest(anchor: window, origin: "LoginPasskeyController.nonDiscoverableLogin")
        func onFailure(error: ReachFiveError) -> Void {
            switch error {
            case ReachFiveError.AuthCanceled:
                #if targetEnvironment(macCatalyst)
                    return
                #else
                Task { @MainActor in
                    try await AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(anchor: window, origin: "LoginPasskeyController.nonDiscoverableLogin.AuthCanceled"))
                        .onSuccess(callback: self.goToProfile)
                        .onFailure { error in
                            let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.localizedDescription)")
                            self.present(alert, animated: true)
                        }
                }
                #endif
            default:
                let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.localizedDescription)")
                self.present(alert, animated: true)
            }
        }
        Task { @MainActor in
            switch (usernameField.text) {
            case .none, .some(""):
                // this is optional, but a good way to present a modal with a fallback to QR code for loging using a nearby device
                try await AppDelegate.reachfive().login(withRequest: request, usingModalAuthorizationFor: [.Passkey], display: .Always)
                    .onSuccess(callback: handleLoginFlow)
                    .onFailure(callback: onFailure)

            case .some(let username):
                try await AppDelegate.reachfive().login(withNonDiscoverableUsername: .Unspecified(username), forRequest: request, usingModalAuthorizationFor: [.Passkey], display: .Always)
                    .onSuccess(callback: goToProfile)
                    .onFailure(callback: onFailure)
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
        let profile: ProfilePasskeySignupRequest
        if (username.contains("@")) {
            profile = ProfilePasskeySignupRequest(email: username)
        } else {
            profile = ProfilePasskeySignupRequest(phoneNumber: username)
        }

        let window: UIWindow = view.window!
        Task { @MainActor in
            try await AppDelegate.reachfive().signup(withRequest: PasskeySignupRequest(passkeyProfile: profile, friendlyName: username, anchor: window, origin: "LoginPasskeyController.createAccount"))
                .onSuccess(callback: goToProfile)
                .onFailure { error in
                    let alert = AppDelegate.createAlert(title: "Signup", message: "Error: \(error.localizedDescription)")
                    self.present(alert, animated: true)
                }
        }
    }

    /// tap anywhere to dismiss the keyboard and access the login and create account buttons
    @IBAction func tappedBackground(_ sender: Any) {
        print("tappedBackground")
        view.endEditing(true)
    }
}
