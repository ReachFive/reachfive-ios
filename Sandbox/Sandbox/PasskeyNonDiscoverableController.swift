import Reach5
import BrightFutures

@available(iOS 16.0, *)
class PasskeyNonDiscoverableController: UIViewController {
    @IBOutlet weak var username: UITextField!
    
    @IBAction func loginWithImmediatelyAvailableCredentials(_ sender: Any) {
        login(display: .IfImmediatelyAvailableCredentials)
    }
    
    @IBAction func loginAlways(_ sender: Any) {
        login(display: .Always)
    }
    
    private func login(display mode: Mode) {
        print("PasskeyNonDiscoverableController.login(display:\(mode))")
        guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
        guard let username = username.text, !username.isEmpty else { return }
        
        let request = NativeLoginRequest(anchor: window, origin: "PasskeyNonDiscoverableController.login")
        AppDelegate.reachfive().login(withNonDiscoverableUsername: .Unspecified(username), forRequest: request, usingModalAuthorizationFor: [.Passkey], display: mode)
            .onSuccess(callback: goToProfile)
            .onFailure { error in
                switch error {
                case .AuthCanceled:
                    return
                default:
                    let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.message())")
                    self.present(alert, animated: true)
                }
            }
    }
}
