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
                Task { @MainActor in
                    self.dismiss(animated: true)
                    await self.handleAuthToken(errorMessage: "Step up failed") {
                        try result.get()
                    }
                }
            }
        }
    }

    @IBAction func passwordEditingDidEnd(_ sender: Any) {
        guard let pass = password.text, !pass.isEmpty, let user = username.text, !user.isEmpty else { return }
        let origin = "NativePasswordController.passwordEditingDidEnd"

        let captcha = CaptchaStore.take()
        Task {
            await handleLoginFlow {
                if user.contains("@") {
                    try await AppDelegate.reachfive().loginWithPassword(email: user, password: pass, origin: origin, captcha: captcha)
                } else {
                    try await AppDelegate.reachfive().loginWithPassword(phoneNumber: user, password: pass, origin: origin, captcha: captcha)
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            let request = NativeLoginRequest(presenting: Presentation(from: self), origin: "NativePasswordController.viewDidAppear")
            await handleLoginFlow {
                try await AppDelegate.reachfive().login(withRequest: request, usingModalAuthorizationFor: [.Password], display: .Always)
            }
        }
    }
}
