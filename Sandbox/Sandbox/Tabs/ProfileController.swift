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
    var profile: Profile = Profile()
    var updatedProfile: ProfileUpdate?
    var trustedDevicesState: DataState<[TrustedDevice]> = .loading
    var mfaCredentials: [MfaCredentialItem] = []
    var passkeys: [DeviceCredential] = []
    
    var editableFields: [(name: String, path: WritableKeyPath<ProfileUpdate, Diff<String>>)] = [
        ("Custom Identifier", \.customIdentifier),
        ("Given Name", \.givenName),
        ("Middle Name", \.middleName),
        ("Family Name", \.familyName),
        ("Nickname", \.nickname),
        ("Username", \.username),
        ("Birthdate", \.birthdate),
        ("Gender", \.gender),
        ("Company", \.company),
        ("Locale", \.locale),
        ("Picture", \.picture)
    ]
    
    var metadataFields: [(name: String, valuef: (Profile) -> String?)] = [
        ("UID", { $0.uid }),
        ("Created At", { $0.createdAt }),
        ("Updated At", { $0.updatedAt }),
        ("Last Login", { $0.loginSummary?.lastLogin.map { date in format(date: date) } }),
        ("Method", { $0.loginSummary?.lastProvider })
    ]
    
    var clearTokenObserver: NSObjectProtocol?
    var setTokenObserver: NSObjectProtocol?
    
    var emailMfaVerifyNotification: NSObjectProtocol?
    var emailVerificationNotification: NSObjectProtocol?
    
    //     var propertiesToDisplay: [Field] = []
    let mfaRegistrationAvailable = ["Email", "Phone Number"]
    var isEditMode = false
    
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
                        self.fetchData() //TODO: recharger seulement la section
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
                        self.fetchData() //TODO: recharger seulement la section
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
        
        profileData.register(UINib(nibName: "ProfileContactInfoCell", bundle: nil), forCellReuseIdentifier: "ProfileContactInfoCell")
        profileData.register(UINib(nibName: "EditableProfileFieldCell", bundle: nil), forCellReuseIdentifier: "EditableProfileFieldCell")
        profileData.register(UINib(nibName: "LogoutCell", bundle: nil), forCellReuseIdentifier: "LogoutCell")
        
        //TODO: supprimer le logout qui n'a jamais marché
        //        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain, target: self, action: #selector(toggleEditMode))
        
    }
    
    //TODO:
    //    @objc func toggleEditMode() {
    //        isEditMode.toggle()
    //        self.navigationItem.rightBarButtonItem?.title = isEditMode ? "Save" : "Edit"
    //        profileData.reloadSections(IndexSet(integer: 1), with: .automatic)
    //
    //        if !isEditMode {
    //            saveProfile()
    //        }
    //    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        print("ProfileController.viewWillAppear")
        fetchData()
    }
    
    
    func fetchData() {
        authToken = AppDelegate.storage.getToken()
        guard let authToken else {
            print("not logged in")
            return
        }
        
        Task {
            
            do {
                let profile = try await AppDelegate.reachfive().getProfile(authToken: authToken)
                let passkeys = await getPasskeysAndSetStatusImage(authToken: authToken)
                self.profile = profile
                self.updatedProfile = profile.asUpdate()
                self.passkeys = passkeys
                
                await fetchTrustedDevices()
                await fetchMfaCredentials(token: authToken)
                
                Task { @MainActor in
                    self.profileData.reloadData()
                }
            } catch {
                self.didLogout()
                Task { @MainActor in
                    if authToken.refreshToken != nil {
                        // the token is probably expired, but it is still possible that it can be refreshed
                        self.profileTabBarItem.image = SandboxTabBarController.tokenExpiredButRefreshable
                        self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
                    } else {
                        self.profileTabBarItem.image = SandboxTabBarController.loggedOut
                        self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
                    }
                }
                print("getProfile error = \(error.localizedDescription)")
            }
        }
    }
    
    func fetchMfaCredentials(token: AuthToken) async {
        do {
            let mfaCredentialsResponse = try await AppDelegate.reachfive().mfaListCredentials(authToken: token)
            self.mfaCredentials = mfaCredentialsResponse.credentials
            await MainActor.run {
                self.profileData.reloadSections(IndexSet(integer: Section.ContactInformation.rawValue), with: .automatic)
            }
        } catch {
            //TODO: peut-être? self.mfaCredentials = .error("Failed to load")
            print("Error fetching MFA credentials: \(error.localizedDescription)")
        }
    }
    
    func fetchTrustedDevices() async {
        guard let token = authToken else { return }
        do {
            print("fetch trusted devices")
            let devices = try await AppDelegate.reachfive().mfaListTrustedDevices(authToken: token)
            print("fetched trusted devices: \(devices)")
            self.trustedDevicesState = .loaded(devices)
        } catch let ReachFiveError.TechnicalError(_, apiError) where apiError?.errorMessageKey == "error.feature.notAvailable" {
            print("error.feature.notAvailable")
            self.trustedDevicesState = .unavailable
        } catch let ReachFiveError.AuthFailure(_, apiError) where apiError?.errorMessageKey == "error.authn.mfa.stepup.required" {
            print("error.authn.mfa.stepup.required")
            self.trustedDevicesState = .stepUpRequired
        } catch {
            self.trustedDevicesState = .error("Failed to load")
            print("Error fetching trusted devices: \(error.localizedDescription)")
        }
        
        await MainActor.run {
            self.profileData.reloadRows(at: [IndexPath(row: SecurityRows.TrustedDevices.rawValue, section: Section.Security.rawValue)], with: .automatic)
        }
    }


//TODO: mettre un DataSate pour les passkeys (et le mfa?) qui peuvent ne pas être frais, ou alors faire un withFreshToken dans le fetchData
    private func getPasskeysAndSetStatusImage(authToken: AuthToken) async -> [DeviceCredential] {
        // Use listWebAuthnCredentials to test if token is fresh
        // A fresh token is also needed for updating the profile and registering MFA credentials
        do {
            let passkeys = try await AppDelegate.reachfive().listWebAuthnCredentials(authToken: authToken)
            Task { @MainActor in
                self.profileTabBarItem.image = SandboxTabBarController.loggedIn
                self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
            }
            return passkeys
        } catch {
            Task { @MainActor in
                self.profileTabBarItem.image = SandboxTabBarController.loggedInButNotFresh
                self.profileTabBarItem.selectedImage = self.profileTabBarItem.image
            }
            return []
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
        Task { @MainActor in
            self.profileData.reloadData()
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

// MARK: - Actions
extension ProfileController {
    func logoutAction(revoke: Bool, webLogout: Bool) {
        Task {
            
            let request: WebSessionLogoutRequest? = if webLogout {
                WebSessionLogoutRequest(presentationContextProvider: self, origin: "ProfileController.logoutAction")
            } else { nil }
            
            let token: AuthToken? = if revoke {
                authToken
            } else { nil }
            try? await AppDelegate.reachfive().logout(webSessionLogout: request, revoke: token)
            AppDelegate.storage.removeToken()
            self.navigationController?.popViewController(animated: true)
        }
    }

    func emailActions() -> [UIAction] {
        var actions: [UIAction] = []
        guard let authToken else {
            return actions
        }
        guard let email = profile.email else {
            actions.append(UIAction(title: "Add Email", handler: { _ in /*self.addEmail()*/ }))
            return actions
        }

        actions.append(UIAction(title: "Update", handler: { _ in /*self.updateEmail()*/ }))
        actions.append(UIAction(title: "Delete", handler: { _ in /*self.deleteEmail()*/ }))
        actions.append(UIAction(title: "Copy", handler: { _ in UIPasteboard.general.string = email }))

        if profile.emailVerified != true {
            actions.append(UIAction(title: "Verify", handler: { _ in /*self.verifyEmail()*/ }))
        }

        let isEnrolled = mfaCredentials.contains { $0.type == .email }
        if isEnrolled {
            actions.append(UIAction(title: "Unenroll MFA", handler: { _ in self.mfaDelete(credential: .Email(), token: authToken) }))
            actions.append(UIAction(title: "Start Step-up", handler: { _ in self.startStepUp(type: .email) }))
        } else {
            actions.append(UIAction(title: "Enroll as MFA", handler: { _ in self.enrollMfaCredential(registering: .Email(), token: authToken) }))
        }

        return actions
    }

    func phoneNumberActions() -> [UIAction] {
        var actions: [UIAction] = []
        guard let authToken else {
            return actions
        }
        guard let phoneNumber = profile.phoneNumber else {
            actions.append(UIAction(title: "Add Phone Number", handler: { _ in /*self.addPhoneNumber()*/ }))
            actions.append(UIAction(title: "Enroll a phone number as MFA", handler: { _ in self.enrollAnotherMfaPhoneNumber(token: authToken) }))
            return actions
        }

        actions.append(UIAction(title: "Update Phone Number", handler: { _ in /*self.updatePhoneNumber()*/ }))
        actions.append(UIAction(title: "Delete Phone Number", handler: { _ in /*self.deletePhoneNumber()*/ }))
        actions.append(UIAction(title: "Copy Phone Number", handler: { _ in UIPasteboard.general.string = phoneNumber }))

        if profile.phoneNumberVerified != true {
            actions.append(UIAction(title: "Verify Phone Number", handler: { _ in /*self.verifyPhoneNumber()*/ }))
        }

        let isEnrolled = mfaCredentials.contains { $0.phoneNumber == phoneNumber }
        if isEnrolled {
            actions.append(UIAction(title: "Unenroll MFA", handler: { _ in self.mfaDelete(credential: .PhoneNumber(phoneNumber), token: authToken) }))
            actions.append(UIAction(title: "Start Step-up", handler: { _ in self.startStepUp(type: .sms) }))
        } else {
            actions.append(UIAction(title: "Enroll this number as MFA", handler: { _ in self.enrollMfaCredential(registering: .PhoneNumber(phoneNumber), token: authToken) }))
            actions.append(UIAction(title: "Enroll another number as MFA", handler: { _ in self.enrollAnotherMfaPhoneNumber(token: authToken) }))
        }

        return actions
    }

    func mfaPhoneNumberActions(for credential: MfaCredentialItem) -> [UIAction] {
        var actions: [UIAction] = []
        guard let authToken else {
            return actions
        }
        if let phoneNumber = credential.phoneNumber {
            actions.append(UIAction(title: "Unenroll MFA", handler: { _ in self.mfaDelete(credential: .PhoneNumber(phoneNumber), token: authToken) }))
        }
        actions.append(UIAction(title: "Start Step-up", handler: { _ in self.startStepUp(type: .sms) }))
        return actions
    }
    
    
    func startStepUp(type: MfaCredentialItemType) {
        guard let authToken else {
            print("not logged in")
            return
        }
        
        let mfaAction = MfaAction(presentationAnchor: self)
        let stepUpFlow = StartStepUp.AuthTokenFlow(authType: type, authToken: authToken, scope: SettingsViewController.selectedScopes)
        
        Task {
            do {
                let freshToken = try await mfaAction.mfaStart(stepUp: stepUpFlow)
                AppDelegate.storage.setToken(freshToken)
                await fetchMfaCredentials(token: freshToken)
                self.presentAlert(title: "Step up", message: "Success")
            } catch {
                self.presentErrorAlert(title: "Step up failed", error)
            }
        }
    }
    
    func enrollMfaCredential(registering credential: Credential, token: AuthToken) {
        let mfaAction = MfaAction(presentationAnchor: self)
        Task {
            do {
                let _ = try await mfaAction.mfaStart(registering: credential, authToken: token)
                await fetchMfaCredentials(token: token)
            } catch {
                self.presentErrorAlert(title: "Enroll failed", error)
            }
        }
    }

    func enrollAnotherMfaPhoneNumber(token: AuthToken) {
        let alert = UIAlertController(title: "Add MFA Credential", message: "Enter a phone number to register a new MFA credential.", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Phone number"
            textField.keyboardType = .phonePad
        }
        let addAction = UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let self, let phoneNumber = alert.textFields?.first?.text, !phoneNumber.isEmpty else { return }
            enrollMfaCredential(registering: .PhoneNumber(phoneNumber), token: token)
        }
        alert.addAction(addAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    func mfaDelete(credential: Credential, token: AuthToken) {
        Task {
            do {
                let cred: String? =
                switch credential {
                case let .PhoneNumber(phoneNumber):
                    phoneNumber
                default:
                    nil
                }
                try await AppDelegate.reachfive().mfaDeleteCredential(cred, authToken: token)
                await fetchMfaCredentials(token: token)
            } catch {
                self.presentErrorAlert(title: "Remove identifier failed", error)
            }
        }
    }
}

extension ProfileController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}

enum DataState<T> {
    case loading
    case loaded(T)
    case error(String)
    case unavailable
    case stepUpRequired
}
