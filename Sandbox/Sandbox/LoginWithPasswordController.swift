import Foundation
import UIKit
import Reach5

//TODO faire que la complétion soit sur email et pas custom identifier par défaut
class LoginWithPasswordController: UIViewController {
    @IBOutlet weak var emailInput: UITextField!
    @IBOutlet weak var phoneNumberInput: UITextField!
    @IBOutlet weak var customIdentifierInput: UITextField!
    @IBOutlet weak var passwordInput: UITextField!
    @IBOutlet weak var error: UILabel!
    var tokenNotification: NSObjectProtocol?

    override func viewDidLoad() {
        print("LoginWithPasswordController.viewDidLoad")
        super.viewDidLoad()
        tokenNotification = NotificationCenter.default.addObserver(forName: .DidReceiveLoginCallback, object: nil, queue: nil) { note in
            if let result = note.userInfo?["result"], let result = result as? Result<AuthToken, ReachFiveError> {
                Task { @MainActor in
                    self.dismiss(animated: true)
                    await self.handleAuthToken(errorMessage: "Step up failed") {
                        try result.get()
                    }
                }
            }
        }
    }

    @IBAction func login(_ sender: Any) {
        Task { @MainActor in
            let email = emailInput.text
            let phoneNumber = phoneNumberInput.text
            let customIdentifier = customIdentifierInput.text
            let password = passwordInput.text ?? ""

            await handleLoginFlow {
                try await AppDelegate.reachfive()
                    .loginWithPassword(email: email, phoneNumber: phoneNumber, customIdentifier: customIdentifier, password: password, origin: "LoginWithPasswordController.loginWithPassword")
            }
        }
    }
}
