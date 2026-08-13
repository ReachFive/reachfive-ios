import Foundation
import Reach5

class PasskeyAutoFillController: UIViewController {

    #if !targetEnvironment(macCatalyst)
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            print("PasskeyAutoFillController.viewDidAppear")

            if #available(iOS 16.0, *) {
                Task {
                    await handleAuthToken {
                        try await AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(presenting: Presentation(from: self), origin: "PasskeyAutoFillController.viewDidAppear"))
                    }
                }
            }
        }
    #endif
}
