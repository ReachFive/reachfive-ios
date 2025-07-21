import Reach5
import UIKit

class PasskeyCredentialController: UIViewController {

    var devices: [DeviceCredential] = [] {
        didSet {
            Task { @MainActor in
                if let header = self.credentialTableview.headerView(forSection: 0) as? EditableSectionHeaderView {
                    header.setEditButtonHidden(self.devices.isEmpty)
                }
            }
        }
    }

    @IBOutlet weak var credentialTableview: UITableView!

    override func viewDidLoad() {
        print("PasskeyCredentialController.viewDidLoad")
        super.viewDidLoad()

        credentialTableview.delegate = self
        credentialTableview.dataSource = self

        let nib = UINib(nibName: "EditableSectionHeaderView", bundle: nil)
        credentialTableview.register(nib, forHeaderFooterViewReuseIdentifier: EditableSectionHeaderView.reuseIdentifier)
    }

    override func viewWillAppear(_ animated: Bool) {
        print("PasskeyCredentialController.viewWillAppear")
        super.viewWillAppear(animated)
        Task {
            if let authToken = AppDelegate.storage.getToken() {
                await self.reloadCredentials(authToken: authToken)
            }
        }
    }

    private func reloadCredentials(authToken: AuthToken) async {
        print(#function)
        var listCredentials: [DeviceCredential] = []
        do {
            listCredentials = try await AppDelegate.withFreshToken(potentiallyStale: authToken) { refreshableToken in
                try await AppDelegate.reachfive().listWebAuthnCredentials(authToken: refreshableToken)
            }
        } catch {
            print("getCredentials error = \(error.localizedDescription)")
        }
        await MainActor.run {
            self.devices = listCredentials
            self.credentialTableview.reloadData()
        }
    }

    @available(iOS 16.0, *)
    func registerNewPasskey() async {
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
                Task {
                    let request = NewPasskeyRequest(anchor: window, friendlyName: textField?.text ?? friendlyName, origin: "ProfileController.registerNewPasskey")
                    do {
                        try await AppDelegate.reachfive().registerNewPasskey(withRequest: request, authToken: authToken)
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
            self.presentErrorAlert(title: "New passkey registration failed", error)
        }
    }
}

extension PasskeyCredentialController: UITableViewDelegate {
    // method to run when table view cell is tapped
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        print(#function)
        guard let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: EditableSectionHeaderView.reuseIdentifier) as? EditableSectionHeaderView else {
            return nil
        }

        var onAdd: (() -> Void)? = nil
        if #available(iOS 16.0, *) {
            onAdd = { [weak self] in
                guard let self else { return }
                Task {
                    await self.registerNewPasskey()
                }
            }
        }

        headerView.configure(
            title: "Passkey Credentials",
            onEdit: { [weak self] button in
                guard let self else { return }
                let isEditing = !self.credentialTableview.isEditing
                self.credentialTableview.setEditing(isEditing, animated: true)
                button.setTitle(isEditing ? "Done" : "Modify", for: .normal)
            },
            onAdd: onAdd
        )
        
        headerView.setEditButtonHidden(devices.isEmpty)
        return headerView
    }
}

extension PasskeyCredentialController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        devices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return credentialTableview.dequeueDefaultReusableCell(withIdentifier: "credentialCell", for: indexPath, text: devices[indexPath.row].friendlyName)
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
                    self.presentErrorAlert(title: "Delete Passkey failed", error)
                }
            }
        }
    }
}