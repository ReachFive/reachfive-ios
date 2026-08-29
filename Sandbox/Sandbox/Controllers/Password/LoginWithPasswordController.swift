import Foundation
import Reach5
import UIKit

// TODO: faire que la complétion soit sur email et pas custom identifier par défaut
// TODO: changer la présentation pour n'avoir qu'un champ identifiant, et un segment control qui gère la signification: email/phone d'un côté, custom identifier de l'autre (voir trois segments pour email/phone/custom identifier)
// TODO: Dynamic Scope Request and Consent: Allow the user to select which scopes to request during the login process
class LoginWithPasswordController: UIViewController {
    @IBOutlet var emailInput: UITextField!
    @IBOutlet var phoneNumberInput: UITextField!
    @IBOutlet var customIdentifierInput: UITextField!
    @IBOutlet var passwordInput: UITextField!
    @IBOutlet var error: UILabel!
    @IBOutlet var scopesTableView: UITableView!

    var tokenNotification: NSObjectProtocol?

    private var availableScopes: [String] = []
    private var selectedScopes: [String] = []

    override func viewDidLoad() {
        print("LoginWithPasswordController.viewDidLoad")
        super.viewDidLoad()

        scopesTableView.dataSource = self
        scopesTableView.delegate = self
        scopesTableView.register(UITableViewCell.self, forCellReuseIdentifier: "scopeCell")

        loadScopes()

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Forgot password?", style: .plain, target: self, action: #selector(forgotPasswordTapped))

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

    private func loadScopes() {
        availableScopes = AppDelegate.reachfive().scope
        selectedScopes = SettingsViewController.selectedScopes
        scopesTableView.reloadData()
    }

    @IBAction func login(_ sender: Any) {
        let email = emailInput.text
        let phoneNumber = phoneNumberInput.text
        let customIdentifier = customIdentifierInput.text
        let password = passwordInput.text ?? ""

        Task {
            await handleLoginFlow {
                try await AppDelegate.reachfive()
                    .loginWithPassword(
                        email: email,
                        phoneNumber: phoneNumber,
                        customIdentifier: customIdentifier,
                        password: password,
                        scope: selectedScopes,
                        origin: "LoginWithPasswordController.loginWithPassword",
                        captcha: CaptchaStore.take()
                    )
            }
        }
    }

    @objc func forgotPasswordTapped() {
        let alert = UIAlertController(title: "Reset Password", message: "Enter your email or phone number.", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Email or phone number"
            textField.autocapitalizationType = .none
        }
        let sendAction = UIAlertAction(title: "Send", style: .default) { [weak self] _ in
            guard let self, let identifier = alert.textFields?.first?.text, !identifier.isEmpty else { return }
            let email = identifier.contains("@") ? identifier : nil
            let phoneNumber = identifier.contains("@") ? nil : identifier
            Task {
                do {
                    try await AppDelegate.reachfive().requestPasswordReset(email: email, phoneNumber: phoneNumber, origin: "LoginWithPasswordController.forgotPassword", captcha: CaptchaStore.take())
                    self.presentAlert(title: "Reset Password", message: "If the account exists, a reset link has been sent.")
                } catch {
                    self.presentErrorAlert(title: "Reset Password failed", error)
                }
            }
        }
        alert.addAction(sendAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc func switchChanged(_ sender: UISwitch) {
        let scope = availableScopes[sender.tag]
        if sender.isOn {
            if !selectedScopes.contains(scope) {
                selectedScopes.append(scope)
            }
        } else {
            selectedScopes.removeAll { $0 == scope }
        }
    }
}

extension LoginWithPasswordController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        availableScopes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "scopeCell", for: indexPath)
        let scope = availableScopes[indexPath.row]
        cell.textLabel?.text = scope
        cell.selectionStyle = .none

        let switchView = UISwitch(frame: .zero)
        switchView.setOn(selectedScopes.contains(scope), animated: false)
        switchView.tag = indexPath.row
        switchView.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)

        cell.accessoryView = switchView

        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Scopes"
    }
}

extension LoginWithPasswordController: UITableViewDelegate {
    // TODO: select all/none
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
