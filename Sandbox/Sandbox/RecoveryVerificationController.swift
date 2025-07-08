import Foundation
import UIKit

class RecoveryVerificationController: UIViewController {
    var email: String?
    var phoneNumber: String?

    @IBOutlet weak var code: UITextField!
    override func viewDidLoad() {
        AppDelegate.reachfive().addAccountRecoveryCallback { result in
            switch result {
            case .success(let resp):
                if let recoveryEndController = self.storyboard?.instantiateViewController(withIdentifier: "AccountRecoveryEnd") as? RecoveryEndController {
                    recoveryEndController.verificationCode = resp.verificationCode
                    recoveryEndController.email = resp.email
                    recoveryEndController.phoneNumber = self.phoneNumber
                    self.navigationController?.pushViewController(recoveryEndController, animated: true)
                }

            case .failure(let error):
                self.presentErrorAlert(title: "Account Recovery Failed", error)
            }
        }
    }


    @IBAction func validate(_ sender: Any) {
        guard let verificationCode = code.text, !verificationCode.isEmpty else {
            print("no code")
            return
        }

        if let recoveryEndController = self.storyboard?.instantiateViewController(withIdentifier: "AccountRecoveryEnd") as? RecoveryEndController {
            recoveryEndController.verificationCode = verificationCode
            recoveryEndController.email = self.email
            recoveryEndController.phoneNumber = self.phoneNumber
            self.navigationController?.pushViewController(recoveryEndController, animated: true)
        }

    }
}
