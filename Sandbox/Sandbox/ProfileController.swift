import UIKit
import Reach5
import BrightFutures

//TODO
//      - déplacer le bouton login with refresh ici pour que, même logué, on puisse afficher les passkey (qui sont expirées)
//      - faire du pull-to-refresh soit sur la table des clés soit carrément sur tout le profil (déclencher le refresh token)
//      - ajouter une option conversion vers un mdp fort automatique et vers SIWA
//      - voir les SLO liés et bouton pour les délier
//      - supprimer le bouton de modification du numéro de téléphone et le mettre en icône crayon à côté de sa valeur affichée (seulement si elle est présente)
//      - faire la même chose pour l'email et custom identifier
//      - pour l'extraction du username, voir la conf backend si la feature SMS est activée.
//      - marquer spécialement l'identifiant principal dans l'UI
//      - ajouter un bouton + dans la table des clés pour en ajouter une (ou carrément supprimer le bouton "register passkey")
//      - ajouter un bouton modifier à la table pour pouvoir plus visuellement supprimer des clés
//      - Ajouter des infos sur le jeton dans une nouvelle page
class ProfileController: UIViewController {
    var authToken: AuthToken?
    var profile: Profile = Profile() {
        didSet {
            self.propertiesToDisplay = [
                Field(name: "Email", value: profile.email?.appending(profile.emailVerified == true ? " ✔︎" : " ✘")),
                Field(name: "Phone Number", value: profile.phoneNumber?.appending(profile.phoneNumberVerified == true ? " ✔︎" : " ✘")),
                Field(name: "Custom Identifier", value: profile.customIdentifier),
                Field(name: "Given Name", value: profile.givenName),
                Field(name: "Family Name", value: profile.familyName),
                Field(name: "Last logged In", value: profile.loginSummary?.lastLogin.map { date in self.format(date: date) } ?? ""),
                Field(name: "Method", value: profile.loginSummary?.lastProvider)
            ]
        }
    }
    
    var clearTokenObserver: NSObjectProtocol?
    var setTokenObserver: NSObjectProtocol?
    
    var emailMfaVerifyNotification: NSObjectProtocol?
    var emailVerificationNotification: NSObjectProtocol?
    
    var propertiesToDisplay: [Field] = []
    let mfaRegistrationAvailable = ["Email", "Phone Number"]
    
    @IBOutlet weak var otherOptions: UITableView!
    
    @IBOutlet weak var profileTabBarItem: UITabBarItem!
    @IBOutlet var profileData: UITableView!
    @IBOutlet weak var mfaButton: UIButton!
    @IBOutlet weak var passkeyButton: UIButton!
    @IBOutlet weak var editProfileButton: UIButton!
    
    override func viewDidLoad() {
        print("ProfileController.viewDidLoad")
        super.viewDidLoad()
        emailMfaVerifyNotification = NotificationCenter.default.addObserver(forName: .DidReceiveMfaVerifyEmail, object: nil, queue: nil) {
            (note) in
            if let result = note.userInfo?["result"], let result = result as? Result<(), ReachFiveError> {
                self.dismiss(animated: true)
                switch result {
                case .success():
                    let alert = AppDelegate.createAlert(title: "Email mfa registering success", message: "Email mfa registering success")
                    self.present(alert, animated: true)
                    self.fetchProfile()
                case .failure(let error):
                    let alert = AppDelegate.createAlert(title: "Email mfa registering failed", message: "Error: \(error.message())")
                    self.present(alert, animated: true)
                }
            }
        }
        emailVerificationNotification = NotificationCenter.default.addObserver(forName: .DidReceiveEmailVerificationCallback, object: nil, queue: nil) {
            (note) in
            if let result = note.userInfo?["result"], let result = result as? Result<(), ReachFiveError> {
                self.dismiss(animated: true)
                switch result {
                case .success():
                    let alert = AppDelegate.createAlert(title: "Email validation success", message: "Email validation success")
                    self.present(alert, animated: true)
                    self.fetchProfile()
                case .failure(let error):
                    let alert = AppDelegate.createAlert(title: "Email validation failed", message: "Error: \(error.message())")
                    self.present(alert, animated: true)
                }
            }
        }
        
        //TODO: mieux gérer les notifications pour ne pas en avoir plusieurs qui se déclenche pour le même évènement
        clearTokenObserver = NotificationCenter.default.addObserver(forName: .DidClearAuthToken, object: nil, queue: nil) { _ in
            self.didLogout()
        }
        
        setTokenObserver = NotificationCenter.default.addObserver(forName: .DidSetAuthToken, object: nil, queue: nil) { _ in
            self.didLogin()
        }
        
        authToken = AppDelegate.storage.getToken()
        if authToken != nil {
            profileTabBarItem.image = SandboxTabBarController.tokenPresent
            profileTabBarItem.selectedImage = profileTabBarItem.image
        }
        
        self.profileData.delegate = self
        self.profileData.dataSource = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        print("ProfileController.viewWillAppear")
        fetchProfile()
    }
    
    func fetchProfile() {
        print("ProfileController.fetchProfile")
        
        authToken = AppDelegate.storage.getToken()
        guard let authToken else {
            print("not logged in")
            return
        }
        AppDelegate.reachfive()
            .getProfile(authToken: authToken)
            .onSuccess { profile in
                self.profile = profile
                self.profileData.reloadData()
                self.setStatusImage(authToken: authToken)
                self.mfaButton.isHidden = false
                self.editProfileButton.isHidden = false
                self.passkeyButton.isHidden = false
            }
            .onFailure { error in
                self.didLogout()
                if authToken.refreshToken != nil {
                    // the token is probably expired, but it is still possible that it can be refreshed
                    self.profileTabBarItem.image = SandboxTabBarController.tokenExpiredButRefreshable
                    self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
                } else {
                    self.profileTabBarItem.image = SandboxTabBarController.loggedOut
                    self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
                }
                print("getProfile error = \(error.message())")
            }
    }
    
    private func setStatusImage(authToken: AuthToken) {
        // Use listWebAuthnCredentials to test if token is fresh
        // A fresh token is also needed for updating the profile and registering MFA credentials
        AppDelegate.reachfive().listWebAuthnCredentials(authToken: authToken).onSuccess { _ in
                self.passkeyButton.isEnabled = true
                self.profileTabBarItem.image = SandboxTabBarController.loggedIn
                self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
            }
            .onFailure { error in
                self.passkeyButton.isEnabled = false
                self.profileTabBarItem.image = SandboxTabBarController.loggedInButNotFresh
                self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
            }
    }
    
    func didLogin() {
        print("ProfileController.didLogin")
        authToken = AppDelegate.storage.getToken()
    }
    
    func didLogout() {
        print("ProfileController.didLogout")
        authToken = nil
        profile = Profile()
        passkeyButton.isHidden = true
        mfaButton.isHidden = true
        editProfileButton.isHidden = true
        self.profileData.reloadData()
    }
    
    @IBAction func logoutAction(_ sender: Any) {
        AppDelegate.reachfive().logout()
            .onComplete { result in
                AppDelegate.storage.removeToken()
                self.navigationController?.popViewController(animated: true)
            }
    }
    
    internal static func username(profile: Profile) -> String {
        let username: String
        // here the priority for phone number over email follows the backend rule
        if let phone = profile.phoneNumber {
            username = phone
        } else if let email = profile.email {
            username = email
        } else {
            username = "Should have had an identifier"
        }
        return username
    }
}
