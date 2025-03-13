import Reach5
import UIKit

class RecoveryVerificationController: UIViewController {
    override func viewDidLoad() {
        AppDelegate.reachfive().addAccountRecoveryCallback { result in
            switch result {
            case .success(let response):
                let email = response.email
                let verificationCode = response.verificationCode
                // show UI for setting up a new passkey or choosing a new password

            case .failure(let error):
                // handle failure
            }
        }
    }
}
