import Foundation
import Reach5
import UIKit

/// The code step of a passwordless flow started by `PasswordlessController`. A magic link opened in the app
/// completes the same flow, through the login callback this screen listens to.
class PasswordlessVerificationController: UIViewController {
    var email: String?
    var phoneNumber: String?

    @IBOutlet var identifierLabel: UILabel!
    @IBOutlet var codeInput: UITextField!

    private var tokenNotification: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        identifierLabel.text = email ?? phoneNumber
        tokenNotification = NotificationCenter.default.addObserver(forName: .DidReceiveLoginCallback, object: nil, queue: nil) { [weak self] note in
            if let self, let result = note.userInfo?["result"], let result = result as? Result<AuthToken, ReachFiveError> {
                Task {
                    await self.handleAuthToken(errorMessage: "Passwordless failed") {
                        try result.get()
                    }
                }
            }
        }
    }

    deinit {
        if let tokenNotification {
            NotificationCenter.default.removeObserver(tokenNotification)
        }
    }

    @IBAction func verify(_ sender: Any) {
        guard let verificationCode = codeInput.text, !verificationCode.isEmpty else { return }

        let verifyAuthCodeRequest = VerifyAuthCodeRequest(
            phoneNumber: phoneNumber,
            email: email,
            verificationCode: verificationCode,
            origin: "PasswordlessVerificationController.verify"
        )
        Task {
            await handleAuthToken(errorMessage: "Verify code failed") {
                try await AppDelegate.reachfive().verifyPasswordlessCode(verifyAuthCodeRequest: verifyAuthCodeRequest)
            }
        }
    }
}
