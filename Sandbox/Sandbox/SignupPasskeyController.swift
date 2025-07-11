import UIKit
import Reach5

class SignupPasskeyController: UIViewController {
    @IBOutlet weak var usernameInput: UITextField!
    @IBOutlet weak var nameInput: UITextField!

    @IBAction func signup(_ sender: Any) {
        guard let username = usernameInput.text, !username.isEmpty else {
            presentAlert(title: "Signup with Passkey", message: "Please provide a username")
            return
        }
        let profile: ProfilePasskeySignupRequest
        if (username.contains("@")) {
            profile = ProfilePasskeySignupRequest(
                email: username,
                name: nameInput.text
            )
        } else {
            profile = ProfilePasskeySignupRequest(
                phoneNumber: username,
                name: nameInput.text
            )
        }

        if #available(iOS 16.0, *) {
            let window: UIWindow = view.window!
            //TODO: est-ce qu'on ne ferait pas une Task.detached, mais on marquerait goToProfile et present(alert) avec Task { @MainActor }
            Task { @MainActor in
                await handleAuthToken(errorMessage: "Signup with Passkey failed") {
                    try await AppDelegate.reachfive().signup(withRequest: PasskeySignupRequest(passkeyProfile: profile, friendlyName: username, anchor: window, origin: "SignupPasskeyController.signup"))
                }
            }
        } else {
            presentAlert(title: "Signup with Passkey failed", message: "Passkey requires iOS 16")
        }
    }
}
