import Foundation
import UIKit
import Reach5

//TODO faire que la complétion soit sur email et pas custom identifier par défaut
class LoginWithPasswordController: UIViewController {
    @IBOutlet weak var emailInput: UITextField!
    @IBOutlet weak var phoneNumberInput: UITextField!
    @IBOutlet weak var customIdentifierInput: UITextField!
    @IBOutlet weak var passwordInput: UITextField!
    @IBOutlet weak var error: UILabel!
    var tokenNotification: NSObjectProtocol?

        
    override func viewDidLoad() {
        print("LoginWithPasswordController.viewDidLoad")
        super.viewDidLoad()
        tokenNotification = NotificationCenter.default.addObserver(forName: .DidReceiveLoginCallback, object: nil, queue: nil) { note in
            if let result = note.userInfo?["result"], let result = result as? Result<AuthToken, ReachFiveError> {
                self.dismiss(animated: true)
                switch result {
                case let .success(authToken):
                    self.goToProfile(authToken)
                case let .failure(error):
                    let alert = AppDelegate.createAlert(title: "Step up failed", message: "Error: \(error.message())")
                    self.present(alert, animated: true)
                }
            }
        }
    }
    
    @IBAction func login(_ sender: Any) {
        Task { @MainActor in
            let email = emailInput.text
            let phoneNumber = phoneNumberInput.text
            let customIdentifier = customIdentifierInput.text
            let password = passwordInput.text ?? ""
            
            print("async loginWithPassword")
            do {
                let resp = try await AppDelegate.reachfive()
                    .loginWithPasswordAsync(email: email, phoneNumber: phoneNumber, customIdentifier: customIdentifier, password: password, origin: "LoginWithPasswordController.loginWithPassword")
                self.error.text = nil
                handleLoginFlow(flow: resp)
            } catch {
                switch error {
                case let rfe as ReachFiveError:
                    self.error.text = rfe.message()
                default:
                    self.error.text = error.localizedDescription
                }
            }
        }
    }
}
