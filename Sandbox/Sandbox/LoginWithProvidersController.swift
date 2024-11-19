import UIKit
import Reach5
import Reach5Facebook
import AppTrackingTransparency
import AuthenticationServices

class LoginWithProvidersController: UIViewController, UITableViewDataSource, UITableViewDelegate, ASWebAuthenticationPresentationContextProviding {
    var providers: [Provider] = []

    @IBOutlet weak var providersTableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()

        providersTableView.dataSource = self
        providersTableView.delegate = self

        providers.append(contentsOf: AppDelegate.reachfive().getProviders())
        providersTableView.reloadData()
        if providers.contains(where: { p in p.name == FacebookProvider.NAME }) {
            ATTrackingManager.requestTrackingAuthorization { status in
                let statut = switch status {
                case ATTrackingManager.AuthorizationStatus.notDetermined: "notDetermined"
                case ATTrackingManager.AuthorizationStatus.restricted:    "restricted"
                case ATTrackingManager.AuthorizationStatus.denied:        "denied"
                case ATTrackingManager.AuthorizationStatus.authorized:    "authorized"
                @unknown default:                                         "unkown"
                }

                print("ATTrackingManager.requestTrackingAuthorization \(statut)")
            }
        }
    }

    public func reloadProvidersData(providers: [Provider]) {
        self.providers = providers
        providersTableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        providers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "providerCell")

        let provider = providers[indexPath.row]

        cell?.textLabel?.text = provider.name

        return cell!
    }

    func handleResult(result: Result<AuthToken, ReachFiveError>) {
        switch result {
        case .success(let authToken):
            goToProfile(authToken)
        case .failure(let error):
            print(error)
            let alert = AppDelegate.createAlert(title: "Login with provider", message: "Error: \(error.message())")
            self.present(alert, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let selectedProvider = providers[indexPath.row]

        let scope = ["openid", "email", "profile", "phone", "full_write", "offline_access"]

        AppDelegate.reachfive()
            .getProvider(name: selectedProvider.name)?
            .login(
                scope: scope,
                origin: "LoginWithProvidersController.didSelectRowAt",
                viewController: self
            )
            .onComplete { result in
                self.handleResult(result: result)
            }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}
