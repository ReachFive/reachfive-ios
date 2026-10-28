import Foundation
import Reach5
import UIKit

/// Starts a passwordless flow on one identifier, the way the recovery screen does: an email sends a code or
/// a magic link, anything else an SMS. The code step continues on `PasswordlessVerificationController`.
///
/// The signup data and the redirect URI are folded by default. Each one is sent only while it is unfolded,
/// so what the screen shows is what the request carries.
class PasswordlessController: UIViewController {
    @IBOutlet var identifierInput: UITextField!

    @IBOutlet var signupDataToggle: UIButton!
    @IBOutlet var signupDataForm: UIStackView!
    @IBOutlet var givenNameInput: UITextField!
    @IBOutlet var familyNameInput: UITextField!
    @IBOutlet var dataEmailInput: UITextField!
    @IBOutlet var dataPhoneNumberInput: UITextField!
    @IBOutlet var consentKeyInput: UITextField!
    @IBOutlet var consentGranted: UISwitch!

    @IBOutlet var redirectUriToggle: UIButton!
    @IBOutlet var redirectUriInput: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        updateChevron(of: signupDataToggle, unfolded: !signupDataForm.isHidden)
        updateChevron(of: redirectUriToggle, unfolded: !redirectUriInput.isHidden)

        // tap anywhere to dismiss the keyboard and access the buttons underneath
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tappedBackground))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func tappedBackground() {
        view.endEditing(true)
    }

    @IBAction func toggleSignupData(_ sender: Any) {
        toggle(signupDataForm, with: signupDataToggle)
    }

    @IBAction func toggleRedirectUri(_ sender: Any) {
        toggle(redirectUriInput, with: redirectUriToggle)
    }

    private func toggle(_ section: UIView, with button: UIButton) {
        UIView.animate(withDuration: 0.25) {
            section.isHidden.toggle()
            self.updateChevron(of: button, unfolded: !section.isHidden)
            self.view.layoutIfNeeded()
        }
    }

    private func updateChevron(of button: UIButton, unfolded: Bool) {
        let chevron = UIImage(systemName: unfolded ? "chevron.down" : "chevron.right")
        if #available(iOS 15.0, *) {
            button.configuration?.image = chevron
            button.configuration?.imagePlacement = .trailing
            button.configuration?.imagePadding = 6
            button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .small)
        } else {
            button.setImage(chevron, for: .normal)
        }
    }

    @IBAction func sendCode(_ sender: Any) {
        guard let identifier = identifierInput.nonEmptyText else { return }
        let email = identifier.contains("@") ? identifier : nil
        let phoneNumber = email == nil ? identifier : nil

        let origin = "PasswordlessController.sendCode"
        let scope = SettingsViewController.selectedScopes

        Task { @MainActor in
            do {
                let redirectUri = try typedRedirectUri()
                let data = signupData()
                let request: PasswordLessRequest = if let email {
                    .Email(email: email, redirectUri: redirectUri, origin: origin)
                } else {
                    .PhoneNumber(phoneNumber: identifier, redirectUri: redirectUri, origin: origin)
                }
                try await AppDelegate.reachfive().startPasswordless(request, scope: scope, data: data, captcha: CaptchaStore.take())

                let verification = storyboard?.instantiateViewController(withIdentifier: "PasswordlessVerification")
                if let verificationController = verification as? PasswordlessVerificationController {
                    verificationController.email = email
                    verificationController.phoneNumber = phoneNumber
                    navigationController?.pushViewController(verificationController, animated: true)
                }
            } catch {
                presentErrorAlert(title: "Passwordless start failed", error)
            }
        }
    }

    /// The unfolded form, or `nil` when it is folded or left empty, so the request then carries no `data` at all.
    private func signupData() -> PasswordlessSignupData? {
        guard !signupDataForm.isHidden else { return nil }

        let consents = consentKeyInput.nonEmptyText.map { key in
            [key: Consent(granted: consentGranted.isOn, consentType: nil, date: ISO8601DateFormatter().string(from: Date()))]
        }
        let fields = [givenNameInput, familyNameInput, dataEmailInput, dataPhoneNumberInput].map(\.nonEmptyText)
        guard consents != nil || fields.contains(where: { $0 != nil }) else { return nil }

        return PasswordlessSignupData(
            email: dataEmailInput.nonEmptyText,
            phoneNumber: dataPhoneNumberInput.nonEmptyText,
            givenName: givenNameInput.nonEmptyText,
            familyName: familyNameInput.nonEmptyText,
            consents: consents
        )
    }

    /// The redirect URI typed in the unfolded field, or `nil` so the SDK falls back to the `SdkConfig` default.
    /// A non-empty entry that does not parse is reported rather than silently dropped: the field exists
    /// precisely to try out one given value.
    private func typedRedirectUri() throws -> URL? {
        guard !redirectUriInput.isHidden, let text = redirectUriInput.nonEmptyText else { return nil }
        guard let uri = URL(string: text) else { throw InvalidRedirectUri(text: text) }
        return uri
    }

    private struct InvalidRedirectUri: LocalizedError {
        let text: String
        var errorDescription: String? {
            "'\(text)' is not a valid URL."
        }
    }
}

private extension UITextField {
    var nonEmptyText: String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
