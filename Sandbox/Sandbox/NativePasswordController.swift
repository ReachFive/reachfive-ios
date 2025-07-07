
import Foundation
import Reach5
import UIKit

class NativePasswordController: UIViewController {
    @IBOutlet var username: UITextField!
    @IBOutlet var password: UITextField!
    var tokenNotification: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        tokenNotification = NotificationCenter.default.addObserver(forName: .DidReceiveLoginCallback, object: nil, queue: nil) { note in
            if let result = note.userInfo?["result"], let result = result as? Result<AuthToken, ReachFiveError> {
                self.dismiss(animated: true)
                switch result {
                case let .success(authToken):
                    self.goToProfile(authToken)
                case let .failure(error):
                    let alert = AppDelegate.createAlert(title: "Step up failed", message: "Error: \(error.localizedDescription)")
                    self.present(alert, animated: true)
                }
            }
        }
    }

    @IBAction func passwordEditingDidEnd(_ sender: Any) {
        Task { @MainActor in
            guard let pass = password.text, !pass.isEmpty, let user = username.text, !user.isEmpty else { return }
            let origin = "NativePasswordController.passwordEditingDidEnd"

            do {
                let flow =
                if user.contains("@") {
                    try await AppDelegate.reachfive().loginWithPassword(email: user, password: pass, origin: origin)
                } else {
                    try await AppDelegate.reachfive().loginWithPassword(phoneNumber: user, password: pass, origin: origin)
                }
                handleLoginFlow(flow: flow)
            } catch {
                let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.localizedDescription)")
                self.present(alert, animated: true)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        Task { @MainActor in
            super.viewDidAppear(animated)

            guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }

            let request = NativeLoginRequest(anchor: window, origin: "NativePasswordController.viewDidAppear")
            do {
                let flow = try await AppDelegate.reachfive().login(withRequest: request, usingModalAuthorizationFor: [.Password], display: .Always)
                handleLoginFlow(flow: flow)
            } catch {
                switch error {
                case ReachFiveError.AuthCanceled: return
                default:
                    let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.localizedDescription)")
                    self.present(alert, animated: true)
                }
            }
        }
    }
}
