import UIKit
import Reach5

class SignupController: UIViewController {
    var initialEmail: String?
    var origin: String = "SignupController.signup"

    @IBOutlet weak var emailInput: UITextField!
    @IBOutlet weak var passwordInput: UITextField!
    @IBOutlet weak var nameInput: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        emailInput.text = initialEmail
    }

    @IBAction func signup(_ sender: Any) {
        let username = emailInput.text ?? ""
        let password = passwordInput.text ?? ""
        let name = nameInput.text ?? ""

        let profile = if (username.contains("@")) {
            ProfileSignupRequest(
                password: password,
                email: username,
                name: name
            )
        } else {
            ProfileSignupRequest(
                password: password,
                phoneNumber: username,
                name: name
            )
        }

        Task {
            await handleAuthToken(errorMessage: "Signup failed") {
                try await AppDelegate.reachfive().signup(profile: profile, origin: origin)
            }
        }
    }
}
