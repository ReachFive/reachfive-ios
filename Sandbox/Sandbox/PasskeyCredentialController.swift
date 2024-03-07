import IdentitySdkCore
import UIKit
import BrightFutures

class PasskeyCredentialController: UIViewController {
    
    var authToken: AuthToken?
    var devices: [DeviceCredential] = [] {
        didSet {
            print("devices \(devices)")
            if devices.isEmpty {
                listPasskeyLabel.isHidden = true
                credentialTableview.isHidden = true
            } else {
                listPasskeyLabel.isHidden = false
                credentialTableview.isHidden = false
            }
        }
    }
    
    @IBOutlet weak var listPasskeyLabel: UILabel!
    @IBOutlet weak var credentialTableview: UITableView!
    @IBOutlet weak var registerPasskeyButton: UIButton!
    
    var clearTokenObserver: NSObjectProtocol?
    var setTokenObserver: NSObjectProtocol?
    
    
    override func viewDidLoad() {
        print("PasskeyCredentialController.viewDidLoad")
        super.viewDidLoad()
        
        credentialTableview.delegate = self
        credentialTableview.dataSource = self
        
        //TODO: mieux gérer les notifications pour ne pas en avoir plusieurs qui se déclenche pour le même évènement
        clearTokenObserver = NotificationCenter.default.addObserver(forName: .DidClearAuthToken, object: nil, queue: nil) { _ in
            self.didLogout()
        }
        
        setTokenObserver = NotificationCenter.default.addObserver(forName: .DidSetAuthToken, object: nil, queue: nil) { _ in
            self.didLogin()
        }
        
        authToken = AppDelegate.storage.get(key: SecureStorage.authKey)
    }
    
    func didLogout() {
        print("PasskeyCredentialController.didLogout")
        authToken = nil
        devices = []
        credentialTableview.reloadData()
        
        registerPasskeyButton.isHidden = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        print("PasskeyCredentialController.viewWillAppear")
        authToken = AppDelegate.storage.get(key: SecureStorage.authKey)
        guard let authToken else {
            print("not logged in")
            return
        }
        
        registerPasskeyButton.isHidden = false
        self.reloadCredentials(authToken: authToken)
        super.viewWillAppear(animated)
    }
    
    func didLogin() {
        print("PasskeyCredentialController.didLogin")
        authToken = AppDelegate.storage.get(key: SecureStorage.authKey)
    }
    
    private func reloadCredentials(authToken: AuthToken) {
        // Beware that a valid token for profile might not be fresh enough to retrieve the credentials
        AppDelegate.reachfive().listWebAuthnCredentials(authToken: authToken).onSuccess { listCredentials in
            self.devices = listCredentials
            
            //TODO comprendre pourquoi on fait un async. En a-t-on vraiment besoin ?
            DispatchQueue.main.async {
                self.credentialTableview.reloadData()
            }
        }
        .onFailure { error in
            self.devices = []
            print("getCredentials error = \(error.message())")
        }
    }
    
    @available(iOS 16.0, *)
    @IBAction func registerNewPasskey(_ sender: Any) {
        print("registerNewPasskey")
        guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
        guard let authToken else {
            print("not logged in")
            return
        }
        AppDelegate.reachfive()
            .getProfile(authToken: authToken)
            .onSuccess { profile in
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
                    
                    AppDelegate.reachfive().registerNewPasskey(withRequest: NewPasskeyRequest(anchor: window, friendlyName: textField?.text ?? friendlyName, origin: "ProfileController.registerNewPasskey"), authToken: authToken)
                        .onSuccess { _ in
                            self.reloadCredentials(authToken: authToken)
                        }
                        .onFailure { error in
                            switch error {
                            case .AuthCanceled: return
                            default:
                                let alert = AppDelegate.createAlert(title: "Register New Passkey", message: "Error: \(error.message())")
                                self.present(alert, animated: true)
                            }
                        }
                }
                alert.addAction(registerAction)
                alert.preferredAction = registerAction
                self.present(alert, animated: true)
            }
            .onFailure { error in
                // the token is probably expired, but it is still possible that it can be refreshed
                self.didLogout()
                print("getProfile error = \(error.message())")
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
        if #available(iOS 14.0, *) {
            var content = cell.defaultContentConfiguration()
            content.text = friendlyName
            cell.contentConfiguration = content
        } else {
            cell.textLabel?.text = friendlyName
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let authToken else { return }
            let element = devices[indexPath.row]
            AppDelegate.reachfive().deleteWebAuthnRegistration(id: element.id, authToken: authToken)
                .onSuccess { _ in
                    self.devices.remove(at: indexPath.row)
                    print("did remove passkey \(element.friendlyName)")
                    tableView.deleteRows(at: [indexPath], with: .fade)
                }
                .onFailure { error in print(error.message()) }
        }
    }
}
