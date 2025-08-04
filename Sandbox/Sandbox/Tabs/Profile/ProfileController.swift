import UIKit
import AuthenticationServices
import Reach5

//TODO:
//      - déplacer le bouton login with refresh ici pour que, même logué, on puisse afficher les passkey (qui sont expirées), ou alors juste faire du withFreshToken lors du clic sur le bouton Manage Passkeys
//      - faire du pull-to-refresh soit sur la table des clés soit carrément sur tout le profil (déclencher le refresh token)
//      - ajouter une option conversion vers un mdp fort automatique et vers SIWA
//      - voir les SLO liés et bouton pour les délier
//      - marquer spécialement l'identifiant principal dans l'UI
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

    @IBOutlet weak var profileTabBarItem: UITabBarItem!
    @IBOutlet var profileData: UITableView!

    override func viewDidLoad() {
        print("ProfileController.viewDidLoad")
        super.viewDidLoad()
        emailMfaVerifyNotification = NotificationCenter.default.addObserver(forName: .DidReceiveMfaVerifyEmail, object: nil, queue: nil) {
            (note) in
            Task { @MainActor in
                if let result = note.userInfo?["result"], let result = result as? Result<(), ReachFiveError> {
                    self.dismiss(animated: true)
                    switch result {
                    case .success():
                        self.presentAlert(title: "Email mfa registering", message: "Email mfa registering success")
                        self.fetchProfile()
                    case .failure(let error):
                        self.presentErrorAlert(title: "Email mfa registering failed", error)
                    }
                }
            }
        }
        emailVerificationNotification = NotificationCenter.default.addObserver(forName: .DidReceiveEmailVerificationCallback, object: nil, queue: nil) {
            (note) in
            Task { @MainActor in
                if let result = note.userInfo?["result"], let result = result as? Result<(), ReachFiveError> {
                    self.dismiss(animated: true)
                    switch result {
                    case .success():
                        self.presentAlert(title: "Email validation", message: "Email validation success")
                        self.fetchProfile()
                    case .failure(let error):
                        self.presentErrorAlert(title: "Email validation failed", error)
                    }
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
        Task { @MainActor in
            do {
                let profile = try await AppDelegate.reachfive().getProfile(authToken: authToken)
                self.profile = profile
                self.profileData.reloadData()

                await self.setStatusImage(authToken: authToken)
            } catch {
                self.didLogout()
                if authToken.refreshToken != nil {
                    // the token is probably expired, but it is still possible that it can be refreshed
                    self.profileTabBarItem.image = SandboxTabBarController.tokenExpiredButRefreshable
                    self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
                } else {
                    self.profileTabBarItem.image = SandboxTabBarController.loggedOut
                    self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
                }
                print("getProfile error = \(error.localizedDescription)")
            }
        }
    }

    private func setStatusImage(authToken: AuthToken) async {
        // Use listWebAuthnCredentials to test if token is fresh
        // A fresh token is also needed for updating the profile and registering MFA credentials
        do {
            let _ = try await AppDelegate.reachfive().listWebAuthnCredentials(authToken: authToken)
            self.profileTabBarItem.image = SandboxTabBarController.loggedIn
            self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
        } catch {
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
        self.profileData.reloadData()
    }

    func logoutAction(_ sender: Any) {
        Task {
            //TODO: options dans l'interface pour choisir les differentes options de logout
            try? await AppDelegate.reachfive().logout(webSessionLogout: WebSessionLogoutRequest(presentationContextProvider: self, origin: "ProfileController.logoutAction"))
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

extension ProfileController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}
