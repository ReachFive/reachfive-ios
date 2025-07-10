import Reach5
import UIKit

class PasskeyCredentialController: UIViewController {

    var devices: [DeviceCredential] = [] {
        didSet {
            print("devices \(devices)")
            Task { @MainActor in
                if devices.isEmpty {
                    listPasskeyLabel.isHidden = true
                    credentialTableview.isHidden = true
                } else {
                    listPasskeyLabel.isHidden = false
                    credentialTableview.isHidden = false
                }
            }
        }
    }

    @IBOutlet weak var listPasskeyLabel: UILabel!
    @IBOutlet weak var credentialTableview: UITableView!
    @IBOutlet weak var registerPasskeyButton: UIButton!

    override func viewDidLoad() {
        print("PasskeyCredentialController.viewDidLoad")
        super.viewDidLoad()

        credentialTableview.delegate = self
        credentialTableview.dataSource = self
    }

    override func viewWillAppear(_ animated: Bool) {
        print("PasskeyCredentialController.viewWillAppear")
        Task { @MainActor in
            super.viewWillAppear(animated)
            if let authToken = AppDelegate.storage.getToken() {
                await self.reloadCredentials(authToken: authToken)
            }
        }
    }

    private func reloadCredentials(authToken: AuthToken) async {
        do {
            let listCredentials = try await AppDelegate.withFreshToken(potentiallyStale: authToken) { refreshableToken in
                try await AppDelegate.reachfive().listWebAuthnCredentials(authToken: refreshableToken)
            }
            self.devices = listCredentials
            Task { @MainActor in
                self.credentialTableview.reloadData()
            }
        } catch {
            self.devices = []
            print("getCredentials error = \(error.localizedDescription)")
        }
    }

    @available(iOS 16.0, *)
    @IBAction func registerNewPasskey(_ sender: Any) {
        Task { @MainActor in
            print("registerNewPasskey")
            guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
            guard let authToken = AppDelegate.storage.getToken() else {
                print("not logged in")
                return
            }
            do {
                let profile = try await AppDelegate.reachfive().getProfile(authToken: authToken)
                let friendlyName = ProfileController.username(profile: profile)

                let alert = UIAlertController(
                    title: "Register New Passkey",
                    message: "Name the passkey",
                    preferredStyle: .alert
                )
                // init the text field with the profile's identifier
                alert.addTextField { field in
                    field.text = friendlyName
                }
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                let registerAction = UIAlertAction(title: "Add", style: .default) { [unowned alert] (_) in
                    let textField = alert.textFields?[0]
                    Task { @MainActor in
                        let request = NewPasskeyRequest(anchor: window, friendlyName: textField?.text ?? friendlyName, origin: "ProfileController.registerNewPasskey")
                        do {
                            try await AppDelegate.withFreshToken(potentiallyStale: authToken) { refreshableToken in
                                try await AppDelegate.reachfive().registerNewPasskey(withRequest: request, authToken: refreshableToken)
                            }
                            await self.reloadCredentials(authToken: authToken)
                        } catch {
                            self.presentErrorAlert(title: "New passkey registration failed", error)
                        }
                    }
                }
                alert.addAction(registerAction)
                alert.preferredAction = registerAction
                self.present(alert, animated: true)
            } catch {
                self.presentErrorAlert(title: "Register New Passkey", error)
            }
        }
    }
}

extension PasskeyCredentialController: UITableViewDelegate {
    // method to run when table view cell is tapped
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension PasskeyCredentialController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        devices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = credentialTableview.dequeueReusableCell(withIdentifier: "credentialCell") else {
            fatalError("No credentialCell cell")
        }

        let friendlyName = devices[indexPath.row].friendlyName
        var content = cell.defaultContentConfiguration()
        content.text = friendlyName
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        Task { @MainActor in
            if editingStyle == .delete {
                guard let authToken = AppDelegate.storage.getToken() else { return }
                let element = devices[indexPath.row]
                do {
                    try await AppDelegate.reachfive().deleteWebAuthnRegistration(id: element.id, authToken: authToken)
                    self.devices.remove(at: indexPath.row)
                    print("did remove passkey \(element.friendlyName)")
                    tableView.deleteRows(at: [indexPath], with: .fade)
                } catch {
                    self.presentErrorAlert(title: "Delete Passkey", error)
                }
            }
        }
    }
}
