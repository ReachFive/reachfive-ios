import Foundation
import UIKit
import Reach5

//TODO: faire que la complétion soit sur email et pas custom identifier par défaut
//TODO: changer la présentation pour n'avoir qu'un champ identifiant, et un segment control qui gère la signification: email/phone d'un côté, custom identifier de l'autre (voir trois segments pour email/phone/custom identifier)
//TODO: Dynamic Scope Request and Consent: Allow the user to select which scopes to request during the login process
class LoginWithPasswordController: UIViewController {
    @IBOutlet weak var emailInput: UITextField!
    @IBOutlet weak var phoneNumberInput: UITextField!
    @IBOutlet weak var customIdentifierInput: UITextField!
    @IBOutlet weak var passwordInput: UITextField!
    @IBOutlet weak var error: UILabel!
    @IBOutlet weak var scopesTableView: UITableView!

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
        self.availableScopes = AppDelegate.reachfive().scope
        self.selectedScopes = SettingsViewController.selectedScopes
        self.scopesTableView.reloadData()
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
                        origin: "LoginWithPasswordController.loginWithPassword"
                    )
            }
        }
    }
}

extension LoginWithPasswordController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return availableScopes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "scopeCell", for: indexPath)
        let scope = availableScopes[indexPath.row]
        cell.textLabel?.text = scope
        cell.accessoryType = selectedScopes.contains(scope) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Scopes"
    }
}

extension LoginWithPasswordController: UITableViewDelegate {

    //TODO: select all/none
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let scope = availableScopes[indexPath.row]
        if let index = selectedScopes.firstIndex(of: scope) {
            selectedScopes.remove(at: index)
        } else {
            selectedScopes.append(scope)
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}
