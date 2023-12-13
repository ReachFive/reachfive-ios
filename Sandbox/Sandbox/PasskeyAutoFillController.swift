import Foundation
import IdentitySdkCore

class PasskeyAutoFillControler: UIViewController {
    
    #if targetEnvironment(macCatalyst)
    #else
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            print("viewDidAppear")
            
            if #available(iOS 16.0, *) {
                guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
                AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(anchor: window, origin: "PasskeyAutoFillControler.viewDidAppear"))
                    .onSuccess(callback: goToProfile)
                    .onFailure { error in
                        let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.message())")
                        self.present(alert, animated: true, completion: nil)
                    }
            }
        }
    #endif
}