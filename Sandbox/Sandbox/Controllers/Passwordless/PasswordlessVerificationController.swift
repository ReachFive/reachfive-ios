import Foundation
import Reach5
import UIKit

/// The code step of a passwordless flow started by `PasswordlessController`, laid out like
/// `RecoveryVerificationController`. A magic link opened in the app completes the same flow, through the
/// login callback this screen listens to.
class PasswordlessVerificationController: UIViewController {
    let username: Username

    @IBOutlet var identifierLabel: UILabel!
    @IBOutlet var codeInput: UITextField!

    private var tokenNotification: NSObjectProtocol?

    init?(coder: NSCoder, username: Username) {
        self.username = username
        super.init(coder: coder)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Instantiate with init(coder:username:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dismissKeyboardOnBackgroundTap()
        identifierLabel.text = username.identifier
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
        guard let verificationCode = codeInput.nonEmptyText else {
            presentAlert(title: "Missing code", message: "Enter the verification code you received.")
            return
        }
        let verifyAuthCodeRequest = VerifyAuthCodeRequest(
            phoneNumber: username.phoneNumber,
            email: username.email,
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
