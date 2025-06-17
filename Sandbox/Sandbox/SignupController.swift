import UIKit
import Reach5

class SignupController: UIViewController {
    var initialEmail: String?
    var origin: String = "SignupController.signup"
    
    @IBOutlet weak var emailInput: UITextField!
    @IBOutlet weak var passwordInput: UITextField!
    @IBOutlet weak var nameInput: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        emailInput.text = initialEmail
    }
    
    @IBAction func signup(_ sender: Any) {
        Task { @MainActor in
            print("Signup async")
            let email = emailInput.text ?? ""
            let password = passwordInput.text ?? ""
            let name = nameInput.text ?? ""
            
            let profile = ProfileSignupRequest(
                password: password,
                email: email,
                name: name
            )
            do {
                let authToken = try await AppDelegate.reachfive().signup(profile: profile, origin: origin)
                goToProfile(authToken)
            } catch {
                let message: String
                switch error {
                case let rfe as ReachFiveError: message = rfe.message()
                default:
                    message = error.localizedDescription
                }
                
                let alert = AppDelegate.createAlert(title: "Signup", message: "Error: \(message)")
                self.present(alert, animated: true)
            }
        }
    }
}
