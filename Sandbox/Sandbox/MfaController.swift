import Foundation
import Reach5
import UIKit

class MfaController: UIViewController {
    @IBOutlet var selectedStepUpType: UISegmentedControl!
    @IBOutlet var startStepUp: UIButton!

    @IBOutlet weak var credentialsTableView: UITableView!
    @IBOutlet weak var trustedDevicesTableView: UITableView!

    static let mfaCell = "MfaCredentialCell"
    static let trustedDeviceCell = "TrustedDeviceCell"

    // The data sources for the table views.
    // A `didSet` observer is used to automatically update the header's edit button visibility
    // whenever the data source changes. This is safe because it does not call `reloadData()`.
    var mfaCredentials: [MfaCredential] = [] {
        didSet {
            updateHeaderVisibility(for: credentialsTableView, isEmpty: mfaCredentials.isEmpty)
        }
    }
    var trustedDevices: [TrustedDevice] = [] {
        didSet {
            updateHeaderVisibility(for: trustedDevicesTableView, isEmpty: trustedDevices.isEmpty)
        }
    }

    var tokenNotification: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()

        credentialsTableView.dataSource = self
        credentialsTableView.delegate = self
        // Register the custom header view's .xib file for the credentials table.
        let credentialsNib = UINib(nibName: "EditableSectionHeaderView", bundle: nil)
        credentialsTableView.register(credentialsNib, forHeaderFooterViewReuseIdentifier: EditableSectionHeaderView.reuseIdentifier)

        trustedDevicesTableView.dataSource = self
        trustedDevicesTableView.delegate = self
        // Register the custom header view's .xib file for the trusted devices table.
        let trustedDevicesNib = UINib(nibName: "EditableSectionHeaderView", bundle: nil)
        trustedDevicesTableView.register(trustedDevicesNib, forHeaderFooterViewReuseIdentifier: EditableSectionHeaderView.reuseIdentifier)


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
            try await fetchMfaCredentials()
            try await fetchTrustedDevices()
        }
    }

    // Safely updates the visibility of the header's edit button on the main thread.
    private func updateHeaderVisibility(for tableView: UITableView, isEmpty: Bool) {
        DispatchQueue.main.async {
            if let header = tableView.headerView(forSection: 0) as? EditableSectionHeaderView {
                header.setEditButtonHidden(isEmpty)
            }
        }
    }

    // Fetches the user's MFA credentials and reloads the table view on the main thread.
    private func fetchMfaCredentials() async throws {
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }
        let response = try await AppDelegate.reachfive().mfaListCredentials(authToken: authToken)
        let credentials = response.credentials.map { MfaCredential.convert(from: $0) }
        await MainActor.run {
            self.mfaCredentials = credentials
            credentialsTableView.reloadData()
        }
    }

    // Fetches the user's trusted devices and reloads the table view on the main thread.
    private func fetchTrustedDevices() async throws {
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }
        var devices: [TrustedDevice] = []
        do {
            devices = try await AppDelegate.reachfive().mfaListTrustedDevices(authToken: authToken)
        } catch let ReachFiveError.TechnicalError(_, apiError) where apiError?.errorMessageKey == "error.feature.notAvailable" {
            print("Trusted device feature not available")
        }
        await MainActor.run {
            self.trustedDevices = devices
            trustedDevicesTableView.reloadData()
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
                try await fetchMfaCredentials()
                self.presentAlert(title: "Step up", message: "Success")
            } catch {
                self.presentErrorAlert(title: "Step up failed", error)
            }
        }
    }

    func addMfaCredential() {
        let alert = UIAlertController(title: "Add MFA Credential", message: "Enter a phone number to register a new MFA credential.", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Phone number"
            textField.keyboardType = .phonePad
        }
        let addAction = UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let self, let phoneNumber = alert.textFields?.first?.text, !phoneNumber.isEmpty else { return }
            self.startMfaPhoneRegistration(phoneNumber: phoneNumber)
        }
        alert.addAction(addAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func startMfaPhoneRegistration(phoneNumber: String) {
        guard let authToken = AppDelegate.storage.getToken() else {
            print("Not logged in")
            return
        }

        let mfaAction = MfaAction(presentationAnchor: self)
        Task {
            do {
                let registeredCredential = try await mfaAction.mfaStart(registering: .PhoneNumber(phoneNumber), authToken: authToken)
                try await fetchMfaCredentials()
                self.presentAlert(title: "MFA \(registeredCredential.type) \(registeredCredential.friendlyName) enabled", message: "Success")
            } catch {
                self.presentErrorAlert(title: "Start MFA Phone Number Registration failed", error)
            }
        }
    }
}

extension MfaController: UITableViewDelegate {
    // method to run when table view cell is tapped
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // Use a custom header view for each section.
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: EditableSectionHeaderView.reuseIdentifier) as? EditableSectionHeaderView else {
            return nil
        }

        if tableView == credentialsTableView {
            headerView.configure(
                title: "Enrolled MFA Credentials",
                onEdit: { [weak self] button in
                    guard let self = self else { return }
                    let isEditing = !self.credentialsTableView.isEditing
                    self.credentialsTableView.setEditing(isEditing, animated: true)
                    button.setTitle(isEditing ? "Done" : "Modify", for: .normal)
                },
                onAdd: { [weak self] in
                    self?.addMfaCredential()
                }
            )
            headerView.setEditButtonHidden(mfaCredentials.isEmpty)
        } else if tableView == trustedDevicesTableView {
            headerView.configure(
                title: "Trusted Devices",
                onEdit: { [weak self] button in
                    guard let self = self else { return }
                    let isEditing = !self.trustedDevicesTableView.isEditing
                    self.trustedDevicesTableView.setEditing(isEditing, animated: true)
                    button.setTitle(isEditing ? "Done" : "Modify", for: .normal)
                }
            )
            headerView.setEditButtonHidden(trustedDevices.isEmpty)
        } else {
            return nil
        }

        return headerView
    }
}

extension MfaController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == credentialsTableView {
            return mfaCredentials.count
        }
        if tableView == trustedDevicesTableView {
            return trustedDevices.count
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == credentialsTableView {
            let credential = mfaCredentials[indexPath.row]
            return tableView.dequeueDefaultReusableCell(withIdentifier: MfaController.mfaCell, for: indexPath, text: credential.identifier, secondaryText: credential.createdAt)
        }
        if tableView == trustedDevicesTableView {
            let device = trustedDevices[indexPath.row]
            return tableView.dequeueDefaultReusableCell(withIdentifier: MfaController.trustedDeviceCell, for: indexPath, text: device.metadata.deviceName ?? "Anonymous device", secondaryText: device.createdAt)
        }
        return UITableViewCell()
    }

    // The commit editing style function enables the swipe-to-delete functionality and responds to the delete action.
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let authToken = AppDelegate.storage.getToken() else { return }
            Task { @MainActor in

                if tableView == credentialsTableView {
                    let element = mfaCredentials[indexPath.row]
                    do {
                        try await AppDelegate.reachfive().mfaDeleteCredential(element.phoneNumber, authToken: authToken)
                        self.mfaCredentials.remove(at: indexPath.row)
                        tableView.deleteRows(at: [indexPath], with: .fade)
                    } catch {
                        self.presentErrorAlert(title: "Remove identifier failed", error)
                    }
                } else if tableView == trustedDevicesTableView {
                    let element = trustedDevices[indexPath.row]
                    do {
                        try await AppDelegate.reachfive().mfaDelete(trustedDeviceId: element.id, authToken: authToken)
                        self.trustedDevices.remove(at: indexPath.row)
                        tableView.deleteRows(at: [indexPath], with: .fade)
                    } catch {
                        self.presentErrorAlert(title: "Remove trusted device failed", error)
                    }
                }
            }
        }
    }
}

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
