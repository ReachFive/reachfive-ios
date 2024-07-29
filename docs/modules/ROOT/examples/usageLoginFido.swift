import UIKit
import IdentitySdkCore
import PromiseKit
import CryptoSwift

class LoginWithFidoViewController: UIViewController{

    @IBOutlet weak var emailText: UITextField!

    let scopes = ["openid", "email", "profile", "phone", "full_write", "offline_access"]

    override func viewDidLoad() {
        super.viewDidLoad()
        AppDelegate.reachfive().initialize().onComplete { _ in }
    }

    @IBAction func loginButton(_ sender: Any) {
        AppDelegate
            .reachfive()
            .loginWithWebAuthn(
                email: self.emailText.text!,
                origin: AppDelegate.origin,
                scopes: scopes,
                viewController: self
            )
            .onSuccess{ authToken in self.goToProfile(authToken) }
            .onFailure { error in
                var messageAlert = ""

                switch error {
                    case .RequestError(let requestErrors):
                        messageAlert = requestErrors.errorDescription!
                    case .TechnicalError(_, let apiError):
                        messageAlert = (apiError?.errorDescription)! as String
                    default:
                        messageAlert = error.localizedDescription
                }

                let alert = UIAlertController(title: "Error", message:messageAlert, preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: "Dismiss", style: UIAlertAction.Style.default, handler: nil))

                self.present(alert, animated: true, completion: nil)
            }
    }

    func goToProfile(_ authToken: AuthToken) {
        AppDelegate.storage.save(key: AppDelegate.authKey, value: authToken)

        let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let profileController = storyBoard.instantiateViewController(
            withIdentifier: "ProfileScene"
        ) as! ProfileController

        profileController.authToken = authToken
        self.self.navigationController?.pushViewController(profileController, animated: true)
    }

}
