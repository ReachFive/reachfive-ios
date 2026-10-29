import Foundation
import UIKit

/// The two endpoints that send a link to an identifier, on one screen: account recovery and password
/// reset. They take the same input and differ only in what the server sends, so a single screen makes
/// the pair easy to compare — reached from the functions list and from the demo screen's
/// "Forgot password?". Laid out like `PasswordlessController`.
///
/// Account recovery continues in the app on a verification screen; a password reset has no in-app
/// step, the account owner finishes on the web page behind the emailed link.
class RecoveryStartController: UIViewController {
    @IBOutlet var identifierInput: UITextField!

    /// Prefilled by whoever pushes this screen, typically with what the user already typed.
    var initialIdentifier: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        dismissKeyboardOnBackgroundTap()
        if let initialIdentifier, !initialIdentifier.isEmpty {
            identifierInput.text = initialIdentifier
        }
    }

    @IBAction func sendLink(_ sender: Any) {
        guard let username = identifierInput.username else { return }

        Task { @MainActor in
            do {
                try await AppDelegate.reachfive().requestAccountRecovery(email: username.email, phoneNumber: username.phoneNumber, origin: "RecoveryStartController.sendLink", captcha: CaptchaStore.take())
                if let verificationController = self.storyboard?.instantiateViewController(identifier: "AccountRecoveryVerification", creator: { coder in
                    RecoveryVerificationController(coder: coder, username: username)
                }) {
                    self.navigationController?.pushViewController(verificationController, animated: true)
                }
            } catch {
                self.presentErrorAlert(title: "Account recovery failed", error)
            }
        }
    }

    @IBAction func sendResetLink(_ sender: Any) {
        guard let username = identifierInput.username else { return }

        Task { @MainActor in
            do {
                try await AppDelegate.reachfive().requestPasswordReset(email: username.email, phoneNumber: username.phoneNumber, origin: "RecoveryStartController.sendResetLink", captcha: CaptchaStore.take())
                self.presentAlert(title: "Reset password", message: "If the account exists, a reset link has been sent.")
            } catch {
                self.presentErrorAlert(title: "Password reset failed", error)
            }
        }
    }
}
