import Foundation
import Reach5
import UIKit

/// The code step of an account recovery started by `RecoveryStartController`, laid out like
/// `PasswordlessVerificationController`. The recovery link opened in the app completes the same step,
/// through the account recovery callback this screen registers.
class RecoveryVerificationController: UIViewController {
    let username: Username

    @IBOutlet var identifierLabel: UILabel!
    @IBOutlet var codeInput: UITextField!

    init?(coder: NSCoder, username: Username) {
        self.username = username
        super.init(coder: coder)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Instantiate with init(coder:username:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dismissKeyboardOnBackgroundTap()
        identifierLabel.text = username.identifier
        AppDelegate.reachfive().addAccountRecoveryCallback { result in
            switch result {
            case let .success(resp):
                self.goToRecoveryEnd(verificationCode: resp.verificationCode, username: .Email(resp.email))

            case let .failure(error):
                self.presentErrorAlert(title: "Account Recovery failed", error)
            }
        }
    }

    @IBAction func verify(_ sender: Any) {
        guard let verificationCode = codeInput.nonEmptyText else { return }

        goToRecoveryEnd(verificationCode: verificationCode, username: username)
    }

    private func goToRecoveryEnd(verificationCode: String, username: Username) {
        if let recoveryEndController = storyboard?.instantiateViewController(identifier: "AccountRecoveryEnd", creator: { coder in
            RecoveryEndController(coder: coder, username: username, verificationCode: verificationCode)
        }) {
            navigationController?.pushViewController(recoveryEndController, animated: true)
        }
    }
}
