import Foundation
import UIKit

/// The two endpoints that send a link to an identifier, on one screen: account recovery and password
/// reset. They take the same input and differ only in what the server sends, so a single screen makes
/// the pair easy to compare — reached from the functions list and from the demo screen's
/// "Forgot password?".
///
/// Account recovery continues in the app on a verification screen; a password reset has no in-app
/// step, the account owner finishes on the web page behind the emailed link.
class RecoveryStartController: UIViewController {
    @IBOutlet var username: UITextField!

    /// Prefilled by whoever pushes this screen, typically with what the user already typed.
    var initialUsername: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        if let initialUsername, !initialUsername.isEmpty {
            username.text = initialUsername
        }
    }

    /// The only heuristic the Sandbox has, the same one `Username.Unspecified` uses.
    private var identifiers: (email: String?, phoneNumber: String?)? {
        guard let username = username.text, !username.isEmpty else { return nil }
        return username.contains("@") ? (username, nil) : (nil, username)
    }

    @IBAction func sendLink(_ sender: Any) {
        guard let (email, phoneNumber) = identifiers else { return }

        Task { @MainActor in
            do {
                try await AppDelegate.reachfive().requestAccountRecovery(email: email, phoneNumber: phoneNumber, origin: "RecoveryStartController:sendLink", captcha: CaptchaStore.take())
                if let verificationController = self.storyboard?.instantiateViewController(withIdentifier: "AccountRecoveryVerification") as? RecoveryVerificationController {
                    verificationController.email = email
                    verificationController.phoneNumber = phoneNumber
                    self.navigationController?.pushViewController(verificationController, animated: true)
                }
            } catch {
                self.presentErrorAlert(title: "Account recovery failed", error)
            }
        }
    }

    @IBAction func sendResetLink(_ sender: Any) {
        guard let (email, phoneNumber) = identifiers else { return }

        Task { @MainActor in
            do {
                try await AppDelegate.reachfive().requestPasswordReset(email: email, phoneNumber: phoneNumber, origin: "RecoveryStartController:sendResetLink", captcha: CaptchaStore.take())
                self.presentAlert(title: "Reset password", message: "If the account exists, a reset link has been sent.")
            } catch {
                self.presentErrorAlert(title: "Password reset failed", error)
            }
        }
    }
}
