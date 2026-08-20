import Reach5
import UIKit

@available(iOS 16.0, *)
class PasskeyNonDiscoverableController: UIViewController {
    @IBOutlet weak var username: UITextField!

    @IBAction func loginWithImmediatelyAvailableCredentials(_ sender: Any) {
        Task {
            await login(display: .IfImmediatelyAvailableCredentials)
        }
    }

    @IBAction func loginAlways(_ sender: Any) {
        Task {
            await login(display: .Always)
        }
    }

    private func login(display mode: Mode) async {
        print("PasskeyNonDiscoverableController.login(display:\(mode))")
        guard let username = username.text, !username.isEmpty else { return }

        let request = NativeLoginRequest(presenting: Presentation(from: self), origin: "PasskeyNonDiscoverableController.login")
        await handleAuthToken {
            try await AppDelegate.reachfive().login(withNonDiscoverableUsername: .Unspecified(username), forRequest: request, usingModalAuthorizationFor: [.Passkey], display: mode)
        }
    }
}
