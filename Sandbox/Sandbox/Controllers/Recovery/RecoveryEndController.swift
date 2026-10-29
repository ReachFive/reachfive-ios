import Foundation
import Reach5
import UIKit

class RecoveryEndController: UIViewController {
    let username: Username
    let verificationCode: String

    @IBOutlet var newPassword: UITextField!

    init?(coder: NSCoder, username: Username, verificationCode: String) {
        self.username = username
        self.verificationCode = verificationCode
        super.init(coder: coder)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Instantiate with init(coder:username:verificationCode:)")
    }

    @IBAction func newPasskey(_ sender: Any) {
        let friendlyName = username.identifier
        Task { @MainActor in
            if #available(iOS 16.0, *) {
                do {
                    try await AppDelegate.reachfive().resetPasskeys(withRequest: ResetPasskeyRequest(verificationCode: verificationCode, friendlyName: friendlyName, presenting: Presentation(from: self), email: username.email, phoneNumber: username.phoneNumber, origin: "RecoveryEndController.newPasskey"))
                    print("reset passkey success")
                    self.navigationController?.popViewController(animated: true)
                    self.navigationController?.popViewController(animated: true)
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    self.presentErrorAlert(title: "Account Recovery failed", error)
                }
            }
        }
    }

    @IBAction func newPassword(_ sender: Any) {
        guard let newPassword = newPassword.text else {
            print("no pass")
            return
        }
        let params: UpdatePasswordParams = switch username {
        case let .Email(email):
            .EmailParams(email: email, verificationCode: verificationCode, password: newPassword)
        case let .PhoneNumber(phoneNumber):
            .SmsParams(phoneNumber: phoneNumber, verificationCode: verificationCode, password: newPassword)
        }
        Task { @MainActor in
            do {
                try await AppDelegate.reachfive().updatePassword(params)
                print("reset password success")
                self.navigationController?.popViewController(animated: true)
                self.navigationController?.popViewController(animated: true)
                self.navigationController?.popViewController(animated: true)
            } catch {
                self.presentErrorAlert(title: "Account Recovery failed", error)
            }
        }
    }
}
