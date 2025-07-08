import Foundation
import UIKit
import Reach5

class PasswordlessController: UIViewController {

    @IBOutlet weak var redirectUriInput: UITextField!
    @IBOutlet weak var emailInput: UITextField!
    @IBOutlet weak var phoneNumberInput: UITextField!
    @IBOutlet weak var verificationCodeInput: UITextField!

    var tokenNotification: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        tokenNotification = NotificationCenter.default.addObserver(forName: .DidReceiveLoginCallback, object: nil, queue: nil) { (note) in
            if let result = note.userInfo?["result"], let result = result as? Result<AuthToken, ReachFiveError> {
                Task { @MainActor in
                    await self.handleAuthToken(errorMessage: "Passwordless failed") {
                        try result.get()
                    }
                }
            }
        }
    }

    @IBAction func loginWithEmail(_ sender: Any) {
        Task { @MainActor in
            try await AppDelegate.reachfive()
                .startPasswordless(
                    .Email(
                        email: emailInput.text ?? "",
                        redirectUri: redirectUriInput.text != "" ? redirectUriInput.text : nil,
                        origin: "PasswordlessController.loginWithEmail"
                    )
                )
                .onSuccess {
                    let alert = AppDelegate.createAlert(title: "Login with email", message: "Success")
                    self.present(alert, animated: true)
                }
                .onFailure { error in
                    let alert = AppDelegate.createAlert(title: "Login with email", message: "Error: \(error.localizedDescription)")
                    self.present(alert, animated: true)
                }
                .onComplete { result in
                    print("startPasswordless email \(result)")
                }
        }
    }

    @IBAction func loginWithPhoneNumber(_ sender: Any) {
        Task { @MainActor in
            try await AppDelegate.reachfive()
                .startPasswordless(
                    .PhoneNumber(
                        phoneNumber: phoneNumberInput.text ?? "",
                        redirectUri: redirectUriInput.text != "" ? redirectUriInput.text : nil,
                        origin: "PasswordlessController.loginWithPhoneNumber"
                    )
                )
                .onSuccess {
                    let alert = AppDelegate.createAlert(title: "Login with phone number", message: "Success")
                    self.present(alert, animated: true)
                }
                .onFailure { error in
                    let alert = AppDelegate.createAlert(title: "Login with phone number", message: "Error: \(error.localizedDescription)")
                    self.present(alert, animated: true)
                }
                .onComplete { result in
                    print("startPasswordless phone number \(result)")
                }
        }
    }

    @IBAction func verifyCode(_ sender: Any) {
        let verifyAuthCodeRequest = VerifyAuthCodeRequest(
            phoneNumber: phoneNumberInput.text,
            email: emailInput.text,
            verificationCode: verificationCodeInput.text ?? "",
            origin: "PasswordlessController.verifyCode"
        )
        Task { @MainActor in
            await handleAuthToken(errorMessage: "Verify code failed") {
                try await AppDelegate.reachfive()
                    .verifyPasswordlessCode(verifyAuthCodeRequest: verifyAuthCodeRequest)
            }
        }
    }
}
