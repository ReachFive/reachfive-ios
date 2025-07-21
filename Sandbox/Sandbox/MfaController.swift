import Foundation
import Reach5
import UIKit

class MfaController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    @IBOutlet var phoneNumberMfaRegistration: UITextField!
    @IBOutlet var selectedStepUpType: UISegmentedControl!
    @IBOutlet var startStepUp: UIButton!

    @IBOutlet weak var credentialsTableView: UITableView!
    @IBOutlet weak var trustedDevicesTableView: UITableView!
    
    static let mfaCell = "MfaCredentialCell"
    static let trustedDeviceCell = "TrustedDeviceCell"

    var mfaCredentials: [MfaCredential] = [] {
        didSet {
            credentialsTableView.reloadData()
        }
    }

    var trustedDevices: [TrustedDevice] = [] {
        didSet {
            trustedDevicesTableView.reloadData()
        }
    }

    var tokenNotification: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()

        credentialsTableView.dataSource = self
        credentialsTableView.delegate = self

        trustedDevicesTableView.dataSource = self
        trustedDevicesTableView.delegate = self

        tokenNotification = NotificationCenter.default.addObserver(forName: .DidReceiveLoginCallback, object: nil, queue: nil) { note in
            Task { @MainActor in
                if let result = note.userInfo?["result"] as? Result<AuthToken, ReachFiveError> {
                    self.dismiss(animated: true)
                    switch result {
                    case let .success(freshToken):
                        AppDelegate.storage.setToken(freshToken)
                        self.presentAlert(title: "Step up", message: "Success")
                    case let .failure(error):
                        self.presentErrorAlert(title: "Step up failed", error)
                    }
                }
            }
        }

        Task {
            await fetchMfaCredentials()
            await fetchTrustedDevices()
        }
    }
    
    private func fetchMfaCredentials() async {
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }
        do {
            let response = try await AppDelegate.reachfive().mfaListCredentials(authToken: authToken)
            self.mfaCredentials = response.credentials.map { MfaCredential.convert(from: $0) }
        } catch {
            self.presentErrorAlert(title: "Load MFA credentials error", error)
        }
    }

    private func fetchTrustedDevices() async {
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }
        do {
            let response = try await AppDelegate.reachfive().mfaListTrustedDevices(authToken: authToken)
            self.trustedDevices = response
        } catch let ReachFiveError.TechnicalError(_, apiError) where apiError?.errorMessageKey == "error.feature.notAvailable" {
            print("Trusted device feature not available")
        } catch {
            self.presentErrorAlert(title: "Load trusted device error", error)
        }
    }

    @IBAction func startStepUp(_ sender: UIButton) {
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }

        let stepUpSelectedType: MfaCredentialItemType = selectedStepUpType.selectedSegmentIndex == 0 ? .email : .sms
        let mfaAction = MfaAction(presentationAnchor: self)
        let stepUpFlow = StartStepUp.AuthTokenFlow(authType: stepUpSelectedType, authToken: authToken, scope: ["openid", "email", "profile", "phone", "full_write", "offline_access", "mfa"])

        Task {
            do {
                let freshToken = try await mfaAction.mfaStart(stepUp: stepUpFlow)
                AppDelegate.storage.setToken(freshToken)
                await fetchMfaCredentials()
                self.presentAlert(title: "Step up", message: "Success")
            } catch {
                self.presentErrorAlert(title: "Step up failed", error)
            }
        }
    }

    @IBAction func startMfaPhoneRegistration(_ sender: UIButton) {
        guard let authToken = AppDelegate.storage.getToken(), let phoneNumber = phoneNumberMfaRegistration.text, !phoneNumber.isEmpty else {
            print("Not logged in or phone number is empty")
            return
        }

        let mfaAction = MfaAction(presentationAnchor: self)
        Task {
            do {
                let registeredCredential = try await mfaAction.mfaStart(registering: .PhoneNumber(phoneNumber), authToken: authToken)
                await fetchMfaCredentials()
                self.presentAlert(title: "MFA \(registeredCredential.type) \(registeredCredential.friendlyName) enabled", message: "Success")
            } catch {
                self.presentErrorAlert(title: "Start MFA Phone Number Registration failed", error)
            }
        }
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == credentialsTableView {
            return mfaCredentials.count
        } else if tableView == trustedDevicesTableView {
            return trustedDevices.count
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == credentialsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: MfaController.mfaCell, for: indexPath)
            let credential = mfaCredentials[indexPath.row]
            
            var content = cell.defaultContentConfiguration()
            
            content.text = credential.identifier
            content.secondaryText = credential.createdAt
            content.prefersSideBySideTextAndSecondaryText = true

            content.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
            content.textProperties.adjustsFontForContentSizeCategory = true
            content.textProperties.adjustsFontSizeToFitWidth = true

            content.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .body)
            content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
            content.secondaryTextProperties.adjustsFontSizeToFitWidth = true
            cell.contentConfiguration = content

            return cell
        } else if tableView == trustedDevicesTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: MfaController.trustedDeviceCell, for: indexPath)
            let device = trustedDevices[indexPath.row]
            
            var content = cell.defaultContentConfiguration()

            content.text = device.metadata.deviceName
            content.secondaryText = device.createdAt
            content.prefersSideBySideTextAndSecondaryText = true

            content.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
            content.textProperties.adjustsFontForContentSizeCategory = true
            content.textProperties.adjustsFontSizeToFitWidth = true

            content.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .body)
            content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
            content.secondaryTextProperties.adjustsFontSizeToFitWidth = true
            cell.contentConfiguration = content
            return cell
        }
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView == credentialsTableView {
            return "Enrolled MFA Credentials"
        } else if tableView == trustedDevicesTableView {
            return "Trusted Devices"
        }
        return nil
    }

    // MARK: - Deletion Logic

    private func deleteCredential(_ credential: MfaCredential) {
        guard let authToken = AppDelegate.storage.getToken() else { return }

        let alert = UIAlertController(title: "Remove Identifier", message: "Are you sure you want to remove \(credential.identifier)?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            Task {
                do {
                    let id = credential.identifier.contains("@") ? nil : credential.identifier
                    try await AppDelegate.reachfive().mfaDeleteCredential(id, authToken: authToken)
                    await self.fetchMfaCredentials()
                } catch {
                    self.presentErrorAlert(title: "Remove identifier failed", error)
                }
            }
        })
        present(alert, animated: true)
    }

    private func deleteTrustedDevice(_ device: TrustedDevice) {
        guard let authToken = AppDelegate.storage.getToken() else { return }

        let alert = UIAlertController(title: "Remove Trusted Device", message: "Are you sure you want to remove this device?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            Task {
                do {
                    try await AppDelegate.reachfive().mfaDelete(trustedDeviceId: device.id, authToken: authToken)
                    await self.fetchTrustedDevices()
                } catch {
                    self.presentErrorAlert(title: "Remove trusted device failed", error)
                }
            }
        })
        present(alert, animated: true)
    }
}

// ... (MfaAction and MfaCredential structs remain the same)
class MfaAction {
    let presentationAnchor: UIViewController

    public init(presentationAnchor: UIViewController) {
        self.presentationAnchor = presentationAnchor
    }

    func mfaStart(registering credential: Credential, authToken: AuthToken) async throws -> MfaCredentialItem {
        let resp = try await AppDelegate.withFreshToken(potentiallyStale: authToken) { refreshableToken in
            try await AppDelegate.reachfive().mfaStart(registering: credential, authToken: refreshableToken)
        }
        return try await self.handleStartVerificationCode(resp)
    }

    func mfaStart(stepUp startStepUp: StartStepUp) async throws -> AuthToken {
        let resp = try await AppDelegate.reachfive().mfaStart(stepUp: startStepUp)
        return try await self.handleStartVerificationCode(resp, stepUpType: startStepUp.authType)
    }

    private func handleStartVerificationCode(_ resp: ContinueStepUp, stepUpType authType: MfaCredentialItemType) async throws -> AuthToken {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let alert = UIAlertController(title: "Verification code", message: "Please enter the verification code you got by \(authType)", preferredStyle: .alert)
                alert.addTextField { textField in
                    textField.placeholder = "Verification code"
                }
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    continuation.resume(throwing: ReachFiveError.AuthCanceled)
                }

                let submitVerificationCode = UIAlertAction(title: "Submit", style: .default) { _ in
                    guard let verificationCode = alert.textFields?[0].text, !verificationCode.isEmpty else {
                        continuation.resume(throwing: ReachFiveError.AuthFailure(reason: "no verification code"))
                        return
                    }
                    continuation.resume {
                        try await resp.verify(code: verificationCode)
                    }
                }
                alert.addAction(cancelAction)
                alert.addAction(submitVerificationCode)
                alert.preferredAction = submitVerificationCode
                presentationAnchor.present(alert, animated: true)
            }
        }
    }

    private func handleStartVerificationCode(_ resp: MfaStartRegistrationResponse) async throws -> MfaCredentialItem {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                switch resp {
                case let .Success(registeredCredential):
                    continuation.resume(returning: registeredCredential)

                case let .VerificationNeeded(continueRegistration):
                    let canal =
                    switch continueRegistration.credentialType {
                    case .Email: "Email"
                    case .PhoneNumber: "SMS"
                    }

                    let alert = UIAlertController(title: "Verification Code", message: "Please enter the verification Code you got by \(canal)", preferredStyle: .alert)
                    alert.addTextField { textField in
                        textField.placeholder = "Verification code"
                    }
                    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
                        continuation.resume(throwing: ReachFiveError.AuthCanceled)
                    }

                    let submitVerificationCode = UIAlertAction(title: "Submit", style: .default) { _ in
                        guard let verificationCode = alert.textFields?[0].text, !verificationCode.isEmpty else {
                            continuation.resume(throwing: ReachFiveError.AuthFailure(reason: "no verification code"))
                            return
                        }
                        continuation.resume {
                            try await continueRegistration.verify(code: verificationCode)
                        }
                    }
                    alert.addAction(cancelAction)
                    alert.addAction(submitVerificationCode)
                    alert.preferredAction = submitVerificationCode
                    presentationAnchor.present(alert, animated: true)
                }
            }
        }
    }
}

struct MfaCredential: Hashable {
    let identifier: String
    let createdAt: String
    let email: String?
    let phoneNumber: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    static func convert(from mfaCredentialItem: MfaCredentialItem) -> MfaCredential {
        let identifier = switch mfaCredentialItem.type {
        case .sms:
            mfaCredentialItem.phoneNumber
        case .email:
            mfaCredentialItem.email
        }
        return MfaCredential(identifier: identifier!, createdAt: mfaCredentialItem.createdAt, email: mfaCredentialItem.email, phoneNumber: mfaCredentialItem.phoneNumber)
    }
}
