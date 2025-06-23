import Foundation
import Reach5
import UIKit

class RecoveryEndController: UIViewController {
    var verificationCode: String?
    var email: String?
    var phoneNumber: String?

    @IBOutlet weak var newPassword: UITextField!

    @IBAction func newPasskey(_ sender: Any) {
        guard let window = self.view.window else { fatalError("The view was not in the app's view hierarchy!") }
        guard let verificationCode else {
            print("no verificationCode")
            return
        }
        guard let username = phoneNumber ?? email else {
            print("no username")
            return
        }
        Task { @MainActor in
            if #available(iOS 16.0, *) {
                await AppDelegate.reachfive().resetPasskeys(withRequest: ResetPasskeyRequest(verificationCode: verificationCode, friendlyName: username, anchor: window, email: email, phoneNumber: phoneNumber, origin: "RecoveryEndController.newPasskey"))
                    .onSuccess { _ in
                        print("succcess reset passkey")
                        self.navigationController?.popViewController(animated: true)
                        self.navigationController?.popViewController(animated: true)
                        self.navigationController?.popViewController(animated: true)
                    }
                    .onFailure { error in
                        print("Error: \(error.message())")
                        let alert = AppDelegate.createAlert(title: "Account Recovery Failed", message: "Error: \(error.message())")
                        self.present(alert, animated: true)
                    }
            }
        }
    }

    @IBAction func newPassword(_ sender: Any) {
        guard let newPassword = newPassword.text else {
            print("no pass")
            return
        }
        guard let verificationCode else {
            print("no verif code")
            return
        }
        if ((phoneNumber ?? email) == nil) {
            print("no username")
            return
        }
        let params: UpdatePasswordParams = if let email {
            .EmailParams(email: email, verificationCode: verificationCode, password: newPassword)
        } else {
            .SmsParams(phoneNumber: phoneNumber!, verificationCode: verificationCode, password: newPassword)
        }
        Task { @MainActor in
            await AppDelegate.reachfive().updatePassword(params)
                .onSuccess { _ in
                    print("succcess reset password")
                    self.navigationController?.popViewController(animated: true)
                    self.navigationController?.popViewController(animated: true)
                    self.navigationController?.popViewController(animated: true)
                }
                .onFailure { error in
                    print("Error: \(error.message())")
                    let alert = AppDelegate.createAlert(title: "Account Recovery Failed", message: "Error: \(error.message())")
                    self.present(alert, animated: true)
                }
        }
    }
}
