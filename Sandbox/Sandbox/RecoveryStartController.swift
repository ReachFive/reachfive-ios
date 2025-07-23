import Foundation
import UIKit

class RecoveryStartController: UIViewController {

    @IBOutlet weak var username: UITextField!

    @IBAction func sendLink(_ sender: Any) {
        guard let username = username.text, !username.isEmpty else { return }
        var email: String?
        var phoneNumber: String?
        if (username.contains("@")) {
            email = username
        } else {
            phoneNumber = username
        }

        //TODO: Ajouter aussi la gestion de "j'ai oublié mon mot de passe"
        Task { @MainActor in
            do {
                try await AppDelegate.reachfive().requestAccountRecovery(email: email, phoneNumber: phoneNumber, origin: "RecoveryStartController:sendLink")
                if let verificationController = self.storyboard?.instantiateViewController(withIdentifier: "AccountRecoveryVerification") as? RecoveryVerificationController {
                    verificationController.email = email
                    verificationController.phoneNumber = phoneNumber
                    self.navigationController?.pushViewController(verificationController, animated: true)
                }
            } catch {
                self.presentErrorAlert(title: "Login failed", error)
            }
        }
    }
}
