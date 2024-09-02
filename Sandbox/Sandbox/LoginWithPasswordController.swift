import Foundation
import UIKit
import Reach5
import BrightFutures

//TODO faire que la complétion soit sur email et pas custom identifier par défaut
class LoginWithPasswordController: UIViewController {
    @IBOutlet weak var emailInput: UITextField!
    @IBOutlet weak var phoneNumberInput: UITextField!
    @IBOutlet weak var customIdentifierInput: UITextField!
    @IBOutlet weak var passwordInput: UITextField!
    @IBOutlet weak var error: UILabel!

    let amrToMfaCredentialItemType = ["sms": MfaCredentialItemType.sms, "email": MfaCredentialItemType.email]
    
    @IBAction func login(_ sender: Any) {
        let email = emailInput.text
        let phoneNumber = phoneNumberInput.text
        let customIdentifier = customIdentifierInput.text
        let password = passwordInput.text ?? ""
        
        AppDelegate.reachfive()
            .loginWithPassword(email: email, phoneNumber: phoneNumber, customIdentifier: customIdentifier, password: password, origin: "LoginWithPasswordController.loginWithPassword")
            .onSuccess (callback: handleFlow)
            .onFailure { error in
                self.error.text = error.message()
            }
    }
}
