import Foundation
import UIKit

class RecoveryVerificationController: UIViewController {
    var email: String?
    var phoneNumber: String?

    @IBOutlet var code: UITextField!
    override func viewDidLoad() {
        AppDelegate.reachfive().addAccountRecoveryCallback { result in
            switch result {
            case let .success(resp):
                if let recoveryEndController = self.storyboard?.instantiateViewController(withIdentifier: "AccountRecoveryEnd") as? RecoveryEndController {
                    recoveryEndController.verificationCode = resp.verificationCode
                    recoveryEndController.email = resp.email
                    recoveryEndController.phoneNumber = self.phoneNumber
                    self.navigationController?.pushViewController(recoveryEndController, animated: true)
                }

            case let .failure(error):
                self.presentErrorAlert(title: "Account Recovery failed", error)
            }
        }
    }

    @IBAction func validate(_ sender: Any) {
        guard let verificationCode = code.text, !verificationCode.isEmpty else {
            print("no code")
            return
        }

        if let recoveryEndController = storyboard?.instantiateViewController(withIdentifier: "AccountRecoveryEnd") as? RecoveryEndController {
            recoveryEndController.verificationCode = verificationCode
            recoveryEndController.email = email
            recoveryEndController.phoneNumber = phoneNumber
            navigationController?.pushViewController(recoveryEndController, animated: true)
        }
    }
}
