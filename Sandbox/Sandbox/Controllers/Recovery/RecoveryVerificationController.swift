import Foundation
import Reach5
import UIKit

/// The code step of an account recovery started by `RecoveryStartController`, laid out like
/// `PasswordlessVerificationController`. The recovery link opened in the app completes the same step,
/// through the account recovery callback this screen registers.
class RecoveryVerificationController: UIViewController {
    var email: String?
    var phoneNumber: String?

    @IBOutlet var identifierLabel: UILabel!
    @IBOutlet var codeInput: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        dismissKeyboardOnBackgroundTap()
        identifierLabel.text = email ?? phoneNumber
        AppDelegate.reachfive().addAccountRecoveryCallback { result in
            switch result {
            case let .success(resp):
                self.goToRecoveryEnd(verificationCode: resp.verificationCode, email: resp.email)

            case let .failure(error):
                self.presentErrorAlert(title: "Account Recovery failed", error)
            }
        }
    }

    @IBAction func verify(_ sender: Any) {
        guard let verificationCode = codeInput.nonEmptyText else { return }

        goToRecoveryEnd(verificationCode: verificationCode, email: email)
    }

    private func goToRecoveryEnd(verificationCode: String, email: String?) {
        if let recoveryEndController = storyboard?.instantiateViewController(withIdentifier: "AccountRecoveryEnd") as? RecoveryEndController {
            recoveryEndController.verificationCode = verificationCode
            recoveryEndController.email = email
            recoveryEndController.phoneNumber = phoneNumber
            navigationController?.pushViewController(recoveryEndController, animated: true)
        }
    }
}
