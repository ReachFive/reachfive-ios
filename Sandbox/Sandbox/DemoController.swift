import AuthenticationServices
import BrightFutures
import Reach5
import UIKit

class DemoController: UIViewController {
    @IBOutlet var usernameLabel: UILabel!
    @IBOutlet var usernameField: UITextField!
    @IBOutlet var passwordLabel: UILabel!
    @IBOutlet var passwordField: UITextField!
    @IBOutlet var loginButton: UIButton!
    @IBOutlet var createAccountButton: UIButton!
    @IBOutlet var loginProviderStackView: UIStackView!
    var tokenNotification: NSObjectProtocol?
    
    override func viewDidLoad() {
        print("DemoController.viewDidLoad")
        super.viewDidLoad()
        tokenNotification = NotificationCenter.default.addObserver(forName: .DidReceiveLoginCallback, object: nil, queue: nil) { note in
            if let result = note.userInfo?["result"], let result = result as? Result<AuthToken, ReachFiveError> {
                self.dismiss(animated: true)
                switch result {
                case let .success(freshToken):
                    self.goToProfile(freshToken)
                case let .failure(error):
                    let alert = AppDelegate.createAlert(title: "Step up failed", message: "Error: \(error.message())")
                    self.present(alert, animated: true)
                }
            }
        }
        // set delegates to manage the keyboard Return/Done button behavior
        usernameField.delegate = self
        passwordField.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        print("DemoController.viewWillAppear")
        usernameField.isHidden = true
        usernameLabel.isHidden = true
        passwordField.isHidden = true
        passwordLabel.isHidden = true
        loginButton.isHidden = true
        createAccountButton.isHidden = true
        loginProviderStackView.isHidden = true
        
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        print("DemoController.viewDidAppear")
        super.viewDidAppear(animated)
        
        guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
        var types: [ModalAuthorization] = [.Password]
        if #available(iOS 16.0, *) {
            types.append(.Passkey)
        }
        let mode: Mode
        if #available(iOS 16.0, *) {
            mode = .IfImmediatelyAvailableCredentials
        } else {
            mode = .Always
        }
        AppDelegate.reachfive().login(withRequest: NativeLoginRequest(anchor: window, origin: "DemoController.viewDidAppear"), usingModalAuthorizationFor: types, display: mode)
            .onSuccess(callback: goToProfile)
            .onFailure { error in
                
                self.usernameField.isHidden = false
                self.usernameLabel.isHidden = false
                self.loginButton.isHidden = false
                self.createAccountButton.isHidden = false
                self.passwordField.isHidden = false
                self.passwordLabel.isHidden = false
                self.loginProviderStackView.isHidden = false
                
                switch error {
                case .AuthCanceled:
                    #if targetEnvironment(macCatalyst)
                        return
                    #else
                        if #available(iOS 16.0, *) {
                            AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(anchor: window, origin: "DemoController.viewDidAppear.AuthCanceled"))
                                .onSuccess(callback: self.goToProfile)
                                .onFailure { error in
                                    print("error: \(error) \(error.message())")
                                }
                        }
                    #endif
                default: return
                }
            }
    }
    
    @IBAction func createAccount(_ sender: Any) {
        guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
        guard let username = usernameField.text else { return }
        
        func goToSignup() {
            if let signupController = storyboard?.instantiateViewController(withIdentifier: "SignupController") as? SignupController {
                signupController.initialEmail = username
                signupController.origin = "DemoController.createAccount"
                navigationController?.pushViewController(signupController, animated: true)
            }
        }
        
        if !username.isEmpty, #available(iOS 16.0, *) {
            let profile: ProfilePasskeySignupRequest
            if username.contains("@") {
                profile = ProfilePasskeySignupRequest(email: username)
            } else {
                profile = ProfilePasskeySignupRequest(phoneNumber: username)
            }
            
            AppDelegate.reachfive().signup(withRequest: PasskeySignupRequest(passkeyProfile: profile, friendlyName: username, anchor: window, origin: "DemoController.createAccount"))
                .onSuccess(callback: goToProfile)
                .onFailure { error in
                    switch error {
                    case .AuthCanceled: goToSignup()
                    default:
                        let alert = AppDelegate.createAlert(title: "Signup", message: "Error: \(error.message())")
                        self.present(alert, animated: true)
                    }
                }
        } else {
            goToSignup()
        }
    }
    
    @IBAction func tappedBackground(_ sender: Any) {
        print("tappedBackground")
        view.endEditing(true)
    }
    
    @IBAction func login(_ sender: Any) {
        guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
        guard let pass = passwordField.text, let username = usernameField.text else { return }
        
        if !pass.isEmpty {
            loginWithPassword()
            return
        }
        
        if #available(iOS 16.0, *) {
            let request = NativeLoginRequest(anchor: window, origin: "DemoController.login")
            
            (username.isEmpty ?
                // this is optional, but a good way to present a modal with a fallback to QR code for loging using a nearby device
                AppDelegate.reachfive().login(withRequest: request, usingModalAuthorizationFor: [.Passkey], display: .Always) :
                AppDelegate.reachfive().login(withNonDiscoverableUsername: .Unspecified(username), forRequest: request, usingModalAuthorizationFor: [.Passkey], display: .Always))
                .onSuccess(callback: goToProfile)
                .onFailure { error in
                    switch error {
                    case .AuthCanceled:
                        #if targetEnvironment(macCatalyst)
                            return
                        #else
                            AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(anchor: window, origin: "DemoController.login.AuthCanceled"))
                                .onSuccess(callback: self.goToProfile)
                                .onFailure { error in
                                    print("error: \(error) \(error.message())")
                                }
                        #endif
                    default:
                        let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.message())")
                        self.present(alert, animated: true)
                    }
                }
        }
    }
    
    func loginWithPassword() {
        guard let pass = passwordField.text, !pass.isEmpty, let user = usernameField.text, !user.isEmpty else { return }
        let origin = "DemoController.loginWithPassword"
        
        let fut: Future<LoginWithPasswordFlow, ReachFiveError>
        if user.contains("@") {
            fut = AppDelegate.reachfive().loginWithPassword(email: user, password: pass, origin: origin)
        } else {
            fut = AppDelegate.reachfive().loginWithPassword(phoneNumber: user, password: pass, origin: origin)
        }
        
        fut.onSuccess(callback: handleLoginWithPassword)
            .onFailure { error in
                let alert = AppDelegate.createAlert(title: "Login", message: "Error: \(error.message())")
                self.present(alert, animated: true)
            }
    }
}

extension DemoController: UITextFieldDelegate {
    // this is called when the Return/Done key is tapped on the keyboard
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // usernameField has tag 0 and passwordField has tag 1
        let nextTag = textField.tag + 1
        let nextTF = textField.superview?.viewWithTag(nextTag) as? UIResponder
        if nextTF != nil {
            // the username field was focused, put focus on the password field
            nextTF?.becomeFirstResponder()
        } else {
            // the password field was focused, defocus it and login
            textField.resignFirstResponder()
            loginWithPassword()
        }
        return false
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {}
    
    func textFieldDidEndEditing(_ textField: UITextField) {}
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        true
    }
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        true
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        true
    }
}
