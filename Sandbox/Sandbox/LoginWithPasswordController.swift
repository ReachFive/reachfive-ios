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
//    weak var authToken: AuthToken?
    let amrToMfaCredentialItemType = ["sms": MfaCredentialItemType.sms, "email": MfaCredentialItemType.email]
    
    @IBAction func login(_ sender: Any) {
        let email = emailInput.text
        let phoneNumber = phoneNumberInput.text
        let customIdentifier = customIdentifierInput.text
        let password = passwordInput.text ?? ""
        
        AppDelegate.reachfive()
            .loginWithPassword(email: email, phoneNumber: phoneNumber, customIdentifier: customIdentifier, password: password, origin: "LoginWithPasswordController.loginWithPassword")
            .onSuccess { token in
                self.error.text = nil
                if(token.token == nil) {
                    self.goToProfile(token)
                } else {
                    let selectMfaAuthTypeAlert = UIAlertController(title: "Select MFA", message: "Select MFA auth type", preferredStyle: UIAlertController.Style.alert)
                    guard let stepUpToken = token.token else {
                        fatalError("Step up token cannot be null")
                    }
                    guard let amrs = token.amr else {
                        fatalError("AMR cannot be null")
                    }
                    amrs.forEach({amr in
                        selectMfaAuthTypeAlert.addAction(self.createSelectMfaAuthTypeAlert(amr: amr, stepUpToken: stepUpToken))
                    })
                    selectMfaAuthTypeAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                    self.present(selectMfaAuthTypeAlert, animated: true, completion: nil)
                }
            }
            .onFailure { error in
                self.error.text = error.message()
            }
    }

    private func createSelectMfaAuthTypeAlert(amr: String, stepUpToken: String) -> UIAlertAction {
        guard let mfaCredentialItemType = self.amrToMfaCredentialItemType[amr] else {
            fatalError("AMR does not exist")
        }
        return UIAlertAction(title: amr, style: .default) { _ in
            AppDelegate().reachfive.mfaStart(stepUp: StartStepUpLoginFlow(authType: mfaCredentialItemType, stepUpToken: stepUpToken)).onSuccess{ resp in
                 self.handleStartVerificationCode(resp, stepUpType: mfaCredentialItemType)
                    .onSuccess{ authTkn in
                        self.goToProfile(authTkn)
                }
            }
        }
    }
    
    private func handleStartVerificationCode(_ resp: ContinueStepUp, stepUpType authType: MfaCredentialItemType) -> Future<AuthToken, ReachFiveError> {
        let promise: Promise<AuthToken, ReachFiveError> = Promise()
        let alert = UIAlertController(title: "Verification code", message: "Please enter the verification code you got by \(authType)", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Verification code"
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            promise.failure(.AuthCanceled)
        }
        
        let submitVerificationCode = UIAlertAction(title: "Submit", style: .default) { _ in
            guard let verificationCode = alert.textFields?[0].text, !verificationCode.isEmpty else {
                print("verification code cannot be empty")
                promise.failure(.AuthFailure(reason: "no verification code"))
                return
            }
            let future = resp.verify(code: verificationCode, trustDevice: true)
            promise.completeWith(future)
            future
                .onSuccess { _ in
                    let alert = AppDelegate.createAlert(title: "Step Up", message: "Success")
                    self.present(alert, animated: true)
                }
                .onFailure { error in
                    let alert = AppDelegate.createAlert(title: "MFA step up failure", message: "Error: \(error.message())")
                    self.present(alert, animated: true)
                }
        }
        alert.addAction(cancelAction)
        alert.addAction(submitVerificationCode)
        alert.preferredAction = submitVerificationCode
        self.present(alert, animated: true)
        return promise.future
    }
    
}
