import Reach5
import UIKit

class SignupPasskeyController: UIViewController {
    @IBOutlet var usernameInput: UITextField!
    @IBOutlet var nameInput: UITextField!

    @IBAction func signup(_ sender: Any) {
        guard let username = usernameInput.text, !username.isEmpty else {
            presentAlert(title: "Signup with Passkey", message: "Please provide a username")
            return
        }
        let profile = if username.contains("@") {
            ProfilePasskeySignupRequest(
                email: username,
                name: nameInput.text
            )
        } else {
            ProfilePasskeySignupRequest(
                phoneNumber: username,
                name: nameInput.text
            )
        }

        if #available(iOS 16.0, *) {
            Task {
                await handleAuthToken(errorMessage: "Signup with Passkey failed") {
                    try await AppDelegate.reachfive().signup(withRequest: PasskeySignupRequest(passkeyProfile: profile, friendlyName: username, presenting: Presentation(from: self), origin: "SignupPasskeyController.signup"))
                }
            }
        } else {
            presentAlert(title: "Signup with Passkey failed", message: "Passkey requires iOS 16")
        }
    }
}
