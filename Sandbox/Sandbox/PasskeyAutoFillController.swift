import Foundation
import Reach5

class PasskeyAutoFillControler: UIViewController {

    #if !targetEnvironment(macCatalyst)
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            print("PasskeyAutoFillControler.viewDidAppear")

            if #available(iOS 16.0, *) {
                Task { @MainActor in
                    guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
                    try await AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(anchor: window, origin: "PasskeyAutoFillControler.viewDidAppear"))
                        .onSuccess(callback: goToProfile)
                        .onFailure { error in
                            let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.localizedDescription)")
                            self.present(alert, animated: true)
                        }
                }
            }
        }
    #endif
}
