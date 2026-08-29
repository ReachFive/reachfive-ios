import Foundation
import UIKit

/// Same shape as `RecoveryStartController`: `requestPasswordReset` has no in-app verification step
/// of its own, the account owner finishes on the web page behind the emailed link.
class PasswordResetController: UIViewController {
    @IBOutlet var username: UITextField!

    var initialUsername: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        username.text = initialUsername
    }

    @IBAction func sendLink(_ sender: Any) {
        guard let username = username.text, !username.isEmpty else { return }
        var email: String?
        var phoneNumber: String?
        if username.contains("@") {
            email = username
        } else {
            phoneNumber = username
        }

        Task { @MainActor in
            do {
                try await AppDelegate.reachfive().requestPasswordReset(email: email, phoneNumber: phoneNumber, origin: "PasswordResetController:sendLink", captcha: CaptchaStore.take())
                self.presentAlert(title: "Reset Password", message: "If the account exists, a reset link has been sent.")
            } catch {
                self.presentErrorAlert(title: "Reset Password failed", error)
            }
        }
    }
}
