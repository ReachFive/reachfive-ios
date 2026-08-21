import Reach5
import UIKit

class SignupController: UIViewController {
    var initialEmail: String?
    var origin: String = "SignupController.signup"
    var emailVerificationNotification: NSObjectProtocol?

    @IBOutlet var emailInput: UITextField!
    @IBOutlet var passwordInput: UITextField!
    @IBOutlet var nameInput: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        emailInput.text = initialEmail
        emailVerificationNotification = NotificationCenter.default.addObserver(forName: .DidReceiveEmailVerificationCallback, object: nil, queue: nil) { note in
            Task { @MainActor in
                if let result = note.userInfo?["result"], let result = result as? Result<Void, ReachFiveError> {
                    self.dismiss(animated: true)
                    switch result {
                    case .success():
                        self.presentAlert(title: "Email validation", message: "Email validation success")
                    case let .failure(error):
                        self.presentErrorAlert(title: "Email validation failed", error)
                    }
                }
            }
        }
    }

    @IBAction func signup(_ sender: Any) {
        let username = emailInput.text ?? ""
        let password = passwordInput.text ?? ""
        let name = nameInput.text ?? ""

        let profile = if username.contains("@") {
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
            let res = try await AppDelegate.reachfive().signup(profile: profile, redirectUrl: AppDelegate.reachfive().sdkConfig.emailVerificationUri, origin: origin)
            return switch res {
            case let .AchievedLogin(authToken): await handleAuthToken(errorMessage: "Signup failed") {
                    authToken
                }
            case .AwaitingIdentifierVerification: presentAlert(title: "Email Verification", message: "Email Verification is required")
            }
        }
    }
}
