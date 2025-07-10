import Reach5

@available(iOS 16.0, *)
class PasskeyNonDiscoverableController: UIViewController {
    @IBOutlet weak var username: UITextField!

    @IBAction func loginWithImmediatelyAvailableCredentials(_ sender: Any) {
        Task { @MainActor in
            await login(display: .IfImmediatelyAvailableCredentials)
        }
    }

    @IBAction func loginAlways(_ sender: Any) {
        Task { @MainActor in
            await login(display: .Always)
        }
    }

    private func login(display mode: Mode) async {
        print("PasskeyNonDiscoverableController.login(display:\(mode))")
        guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
        guard let username = username.text, !username.isEmpty else { return }

        let request = NativeLoginRequest(anchor: window, origin: "PasskeyNonDiscoverableController.login")
        await handleAuthToken {
            try await AppDelegate.reachfive().login(withNonDiscoverableUsername: .Unspecified(username), forRequest: request, usingModalAuthorizationFor: [.Passkey], display: mode)
        }
    }
}
