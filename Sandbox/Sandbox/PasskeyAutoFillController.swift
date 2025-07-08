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
                    await handleAuthToken {
                        try await AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(anchor: window, origin: "PasskeyAutoFillControler.viewDidAppear"))
                    }
                }
            }
        }
    #endif
}
