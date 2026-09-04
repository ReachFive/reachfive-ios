import Foundation
import Reach5
import UIKit

class PasswordlessController: UIViewController {
    @IBOutlet var redirectUriInput: UITextField!
    @IBOutlet var emailInput: UITextField!
    @IBOutlet var phoneNumberInput: UITextField!
    @IBOutlet var verificationCodeInput: UITextField!

    var tokenNotification: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        tokenNotification = NotificationCenter.default.addObserver(forName: .DidReceiveLoginCallback, object: nil, queue: nil) { note in
            if let result = note.userInfo?["result"], let result = result as? Result<AuthToken, ReachFiveError> {
                Task {
                    await self.handleAuthToken(errorMessage: "Passwordless failed") {
                        try result.get()
                    }
                }
            }
        }
    }

    @IBAction func loginWithEmail(_ sender: Any) {
        Task {
            do {
                try await AppDelegate.reachfive()
                    .startPasswordless(
                        .Email(
                            email: emailInput.text ?? "",
                            redirectUri: typedRedirectUri(),
                            origin: "PasswordlessController.loginWithEmail"
                        ),
                        captcha: CaptchaStore.take()
                    )
                self.presentAlert(title: "Login with email", message: "Success")
            } catch {
                self.presentErrorAlert(title: "Login with email failed", error)
            }
        }
    }

    @IBAction func loginWithPhoneNumber(_ sender: Any) {
        Task {
            do {
                try await AppDelegate.reachfive()
                    .startPasswordless(
                        .PhoneNumber(
                            phoneNumber: phoneNumberInput.text ?? "",
                            redirectUri: typedRedirectUri(),
                            origin: "PasswordlessController.loginWithPhoneNumber"
                        ),
                        captcha: CaptchaStore.take()
                    )
                self.presentAlert(title: "Login with phone number", message: "Success")
            } catch {
                self.presentErrorAlert(title: "Login with phone number failed", error)
            }
        }
    }

    /// The redirect URI typed in the field, or `nil` when it is left empty so the SDK falls back to the
    /// `SdkConfig` default. A non-empty entry that does not parse is reported rather than silently dropped:
    /// the field exists precisely to try out one given value.
    private func typedRedirectUri() throws -> URL? {
        guard let text = redirectUriInput.text, !text.isEmpty else { return nil }
        guard let uri = URL(string: text) else { throw InvalidRedirectUri(text: text) }
        return uri
    }

    private struct InvalidRedirectUri: LocalizedError {
        let text: String
        var errorDescription: String? {
            "'\(text)' is not a valid URL."
        }
    }

    @IBAction func verifyCode(_ sender: Any) {
        let verifyAuthCodeRequest = VerifyAuthCodeRequest(
            phoneNumber: phoneNumberInput.text,
            email: emailInput.text,
            verificationCode: verificationCodeInput.text ?? "",
            origin: "PasswordlessController.verifyCode"
        )
        Task {
            await handleAuthToken(errorMessage: "Verify code failed") {
                try await AppDelegate.reachfive().verifyPasswordlessCode(verifyAuthCodeRequest: verifyAuthCodeRequest)
            }
        }
    }
}
