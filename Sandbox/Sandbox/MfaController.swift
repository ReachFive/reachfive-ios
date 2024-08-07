import BrightFutures
import Foundation
import Reach5
import UIKit

class MfaController: UIViewController {
    @IBOutlet var phoneNumberMfaRegistration: UITextField!
    
    var listMfaCredentialsView: UICollectionView! = nil
    
    var listMfaTrustedDevicesView: UICollectionView! = nil
    
    @IBOutlet var selectedStepUpType: UISegmentedControl!
    
    @IBOutlet var startStepUp: UIButton!
    
    enum Section {
        case main
        case trusted
    }
    
    var listMfaCredentialsDataSource: UICollectionViewDiffableDataSource<Section, MfaCredential>! = nil
    
    var currentListMfaCredentialSnapshot: NSDiffableDataSourceSnapshot<Section, MfaCredential>! = nil
    
    var listMfaTrustedDevicesDataSource: UICollectionViewDiffableDataSource<Section, TrustedDevice>! = nil
    
    var currentListMfaTrustedDeviceSnapshot: NSDiffableDataSourceSnapshot<Section, TrustedDevice>! = nil
    
    var mfaCredentialsToDisplay: [MfaCredential] = [] {
        didSet {
            currentListMfaCredentialSnapshot.appendItems(mfaCredentialsToDisplay)
            listMfaCredentialsDataSource.apply(currentListMfaCredentialSnapshot)
        }
    }
    
    var mfaTrustedDevicesToDisplay: [TrustedDevice] = [] {
        didSet {
            currentListMfaTrustedDeviceSnapshot.appendItems(mfaTrustedDevicesToDisplay)
            listMfaTrustedDevicesDataSource.apply(currentListMfaTrustedDeviceSnapshot)
        }
    }
    
    var tokenNotification: NSObjectProtocol?
    
    private func fetchMfaCredentials() {
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }
        AppDelegate.reachfive()
            .mfaListCredentials(authToken: authToken)
            .onSuccess { response in
                self.mfaCredentialsToDisplay = response.credentials.map { MfaCredential.convert(from: $0) }
            }
    }
    
    private func fetchTrustedDevices() {
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }
        AppDelegate.reachfive()
            .mfaListTrustedDevices(authToken: authToken)
            .onSuccess { response in
                self.mfaTrustedDevicesToDisplay = response
            }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tokenNotification = NotificationCenter.default.addObserver(forName: .DidReceiveLoginCallback, object: nil, queue: nil) { note in
            if let result = note.userInfo?["result"], let result = result as? Result<AuthToken, ReachFiveError> {
                self.dismiss(animated: true)
                switch result {
                case let .success(freshToken):
                    AppDelegate.storage.setToken(freshToken)
                    let alert = AppDelegate.createAlert(title: "Step up", message: "Success")
                    self.present(alert, animated: true)
                case let .failure(error):
                    let alert = AppDelegate.createAlert(title: "Step failed", message: "Error: \(error.message())")
                    self.present(alert, animated: true)
                }
            }
        }

        configureHierarchy()
        configureDataSource()
        fetchMfaCredentials()
        fetchTrustedDevices()
    }
    
    @IBAction func startStepUp(_ sender: UIButton) {
        print("MfaController.startStepUp")
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }

        let stepUpSelectedType = switch selectedStepUpType.selectedSegmentIndex {
        case 0:
            MfaCredentialItemType.email
        default:
            MfaCredentialItemType.sms
        }
        let mfaAction = MfaAction(presentationAnchor: self)
        
        mfaAction.mfaStart(stepUp: StartStepUp(authType: stepUpSelectedType, authToken: authToken, scope: ["openid", "email", "profile", "phone", "full_write", "offline_access", "mfa"]), authToken: authToken).onSuccess { freshToken in
            AppDelegate.storage.setToken(freshToken)
            self.fetchTrustedDevices()
        }
    }
    
    @IBAction func startMfaPhoneRegistration(_ sender: UIButton) {
        print("MfaController.startMfaPhoneRegistration")
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }
        guard let phoneNumber = phoneNumberMfaRegistration.text else {
            print("phone number cannot be empty")
            return
        }
        
        let mfaAction = MfaAction(presentationAnchor: self)
        mfaAction.mfaStart(registering: .PhoneNumber(phoneNumber), authToken: authToken).onSuccess { _ in
            self.fetchMfaCredentials()
        }
    }
}

class MfaAction {
    let presentationAnchor: UIViewController
    
    public init(presentationAnchor: UIViewController) {
        self.presentationAnchor = presentationAnchor
    }
    
    func mfaStart(registering credential: Credential, authToken: AuthToken) -> Future<MfaCredentialItem, ReachFiveError> {
        let future = AppDelegate.reachfive()
            .mfaStart(registering: credential, authToken: authToken)
            .recoverWith { error in
                guard case let .AuthFailure(reason: _, apiError: apiError) = error,
                      let key = apiError?.errorMessageKey,
                      key == "error.accessToken.freshness"
                else {
                    return Future(error: error)
                }
                
                // Automatically refresh the token if it is stale
                return AppDelegate.reachfive()
                    .refreshAccessToken(authToken: authToken).flatMap { (freshToken: AuthToken) in
                        AppDelegate.storage.setToken(freshToken)
                        return AppDelegate.reachfive()
                            .mfaStart(registering: credential, authToken: freshToken)
                    }
            }
            .flatMap { resp in
                self.handleStartVerificationCode(resp)
            }
            .onFailure { error in
                let alert = AppDelegate.createAlert(title: "Start MFA \(credential.credentialType) Registration", message: "Error: \(error.message())")
                self.presentationAnchor.present(alert, animated: true)
            }
        
        return future
    }
    
    func mfaStart(stepUp startStepUp: StartStepUp, authToken: AuthToken) -> Future<AuthToken, ReachFiveError> {
        return AppDelegate.reachfive()
            .mfaStart(stepUp: startStepUp)
            .recoverWith { error in
                guard case let .AuthFailure(reason: _, apiError: apiError) = error,
                      let key = apiError?.errorMessageKey,
                      key == "error.accessToken.freshness"
                else {
                    return Future(error: error)
                }

                return AppDelegate.reachfive()
                    .refreshAccessToken(authToken: authToken).flatMap { (freshToken: AuthToken) in
                        AppDelegate.storage.setToken(freshToken)
                        return AppDelegate.reachfive()
                            .mfaStart(stepUp: startStepUp)
                    }
            }
            .flatMap { resp in
                self.handleStartVerificationCode(resp, stepUpType: startStepUp.authType)
            }
            .onFailure { error in
                let alert = AppDelegate.createAlert(title: "Step up", message: "Error: \(error.message())")
                self.presentationAnchor.present(alert, animated: true)
            }
    }
    
    private func handleStartVerificationCode(_ resp: ContinueStepUp, stepUpType authType: MfaCredentialItemType) -> Future<AuthToken, ReachFiveError> {
        let promise: Promise<AuthToken, ReachFiveError> = Promise()
        let alert = UIAlertController(title: "Verification code", message: "Please enter the verification code you got by \(authType)", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Verification code"
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            promise.failure(.AuthCanceled)
        }
        
        let submitVerificationCode = UIAlertAction(title: "Submit", style: .default) { _ in
            guard let verificationCode = alert.textFields?[0].text, !verificationCode.isEmpty else {
                print("verification code cannot be empty")
                promise.failure(.AuthFailure(reason: "no verification code"))
                return
            }
            let future = resp.verify(code: verificationCode)
            promise.completeWith(future)
            future
                .onSuccess { _ in
                    let alert = AppDelegate.createAlert(title: "Step Up", message: "Success")
                    self.presentationAnchor.present(alert, animated: true)
                }
                .onFailure { error in
                    let alert = AppDelegate.createAlert(title: "MFA step up failure", message: "Error: \(error.message())")
                    self.presentationAnchor.present(alert, animated: true)
                }
        }
        alert.addAction(cancelAction)
        alert.addAction(submitVerificationCode)
        alert.preferredAction = submitVerificationCode
        presentationAnchor.present(alert, animated: true)
        return promise.future
    }
    
    private func handleStartVerificationCode(_ resp: MfaStartRegistrationResponse) -> Future<MfaCredentialItem, ReachFiveError> {
        let promise: Promise<MfaCredentialItem, ReachFiveError> = Promise()
        switch resp {
        case let .Success(registeredCredential):
            let alert = AppDelegate.createAlert(title: "MFA \(registeredCredential.type) \(registeredCredential.friendlyName) enabled", message: "Success")
            presentationAnchor.present(alert, animated: true)
            promise.success(registeredCredential)
        
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
                promise.failure(.AuthCanceled)
            }
            
            let submitVerificationCode = UIAlertAction(title: "Submit", style: .default) { _ in
                guard let verificationCode = alert.textFields?[0].text, !verificationCode.isEmpty else {
                    print("verification code cannot be empty")
                    promise.failure(.AuthFailure(reason: "no verification code"))
                    return
                }
                let future = continueRegistration.verify(code: verificationCode)
                promise.completeWith(future)
                future
                    .onSuccess { succ in
                        let alert = AppDelegate.createAlert(title: "Verify MFA \(succ.type) registration", message: "Success")
                        self.presentationAnchor.present(alert, animated: true)
                    }
                    .onFailure { error in
                        let alert = AppDelegate.createAlert(title: "MFA \(continueRegistration.credentialType) failure", message: "Error: \(error.message())")
                        self.presentationAnchor.present(alert, animated: true)
                    }
            }
            alert.addAction(cancelAction)
            alert.addAction(submitVerificationCode)
            alert.preferredAction = submitVerificationCode
            presentationAnchor.present(alert, animated: true)
        }
        return promise.future
    }
}

extension MfaController {
    func createLayout(_ elementKind: String) -> UICollectionViewLayout {
        let sectionProvider = { (_: Int,
                                 _: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                      heightDimension: .fractionalHeight(0.1))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                    
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.95),
                                                       heightDimension: .absolute(250))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
            
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)

                let titleSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                       heightDimension: .estimated(22))
                let titleSupplementary = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: titleSize,
                    elementKind: elementKind,
                    alignment: .top)
                titleSupplementary.pinToVisibleBounds = true
                section.boundarySupplementaryItems = [titleSupplementary]
                return section
        }

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 20

        let layout = UICollectionViewCompositionalLayout(
            sectionProvider: sectionProvider, configuration: config)
        return layout
    }
    
    func configureHierarchy() {
        listMfaCredentialsView = UICollectionView(frame: .zero, collectionViewLayout: createLayout("Mfa credentials"))
        listMfaCredentialsView?.translatesAutoresizingMaskIntoConstraints = false
        listMfaTrustedDevicesView = UICollectionView(frame: .zero, collectionViewLayout: createLayout("Mfa trusted devices"))
        listMfaTrustedDevicesView?.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(listMfaCredentialsView)
        view.addSubview(listMfaTrustedDevicesView)
        NSLayoutConstraint.activate([
            listMfaCredentialsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listMfaCredentialsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listMfaCredentialsView.topAnchor.constraint(equalTo: view.topAnchor, constant: view.frame.height/2),
            listMfaCredentialsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            listMfaTrustedDevicesView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listMfaTrustedDevicesView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listMfaTrustedDevicesView.topAnchor.constraint(equalTo: view.topAnchor, constant: view.frame.height/(1.5)),
            listMfaTrustedDevicesView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<CredentialCollectionViewCell, MfaCredential> { cell, _, credential in
            cell.configure(with: credential)
        }
        listMfaCredentialsDataSource = UICollectionViewDiffableDataSource<Section, MfaCredential>(collectionView: listMfaCredentialsView) {
            (collectionView: UICollectionView, indexPath: IndexPath, credential: MfaCredential) -> UICollectionViewCell? in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: credential)
        }
        let supplementaryRegistration = UICollectionView.SupplementaryRegistration
        <TitleSupplementaryView>(elementKind: "Mfa credentials") {
            (supplementaryView, _, _) in
            supplementaryView.label.text = "Enrolled MFA credentials"
        }
        
        listMfaCredentialsDataSource.supplementaryViewProvider = { _, _, index in
            self.listMfaCredentialsView.collectionViewLayout.collectionView?.dequeueConfiguredReusableSupplementary(
                using: supplementaryRegistration, for: index)
        }
        currentListMfaCredentialSnapshot = NSDiffableDataSourceSnapshot
        <Section, MfaCredential>()
        currentListMfaCredentialSnapshot.appendSections([.main])
        currentListMfaCredentialSnapshot.appendItems(mfaCredentialsToDisplay)
        listMfaCredentialsDataSource.apply(currentListMfaCredentialSnapshot, animatingDifferences: false)
        
        
        let cellTrustedDeviceRegistration = UICollectionView.CellRegistration<TrustedDeviceCollectionViewCell, TrustedDevice> { cell, _, trustedDevice in
            cell.configure(with: trustedDevice)
        }
        listMfaTrustedDevicesDataSource = UICollectionViewDiffableDataSource<Section, TrustedDevice>(collectionView: listMfaTrustedDevicesView) {
            (collectionView: UICollectionView, indexPath: IndexPath, trustedDevice: TrustedDevice) -> UICollectionViewCell? in
            collectionView.dequeueConfiguredReusableCell(using: cellTrustedDeviceRegistration, for: indexPath, item: trustedDevice)
        }
        
        let supplementaryTrustedDeviceRegistration = UICollectionView.SupplementaryRegistration<TitleSupplementaryView>(elementKind: "Mfa trusted devices") {
            (supplementaryView, _, _) in
            supplementaryView.label.text = "Added trusted devices"
        }
        listMfaTrustedDevicesDataSource.supplementaryViewProvider = { _, _, index in
            self.listMfaTrustedDevicesView.collectionViewLayout.collectionView?
                .dequeueConfiguredReusableSupplementary(using: supplementaryTrustedDeviceRegistration, for: index)
        }
        currentListMfaTrustedDeviceSnapshot = NSDiffableDataSourceSnapshot<Section, TrustedDevice>()
        currentListMfaTrustedDeviceSnapshot.appendSections([.trusted])
        currentListMfaTrustedDeviceSnapshot.appendItems(mfaTrustedDevicesToDisplay)
        listMfaTrustedDevicesDataSource.apply(currentListMfaTrustedDeviceSnapshot, animatingDifferences: false)
        
    }
}

class TrustedDeviceCollectionViewCell: UICollectionViewListCell {
    static let identifier = "TrustedDeviceCollectionViewCell"
    
    let id: UILabel = {
        let label = UILabel()
        return label
    }()
    
    let userId: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)

        return label
    }()
    
    let ip: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)

        return label
    }()
    
    let createdAt: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)

        return label
    }()
    
    let operatingSystem: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)

        return label
    }()
    
    let deviceClass: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)

        return label
    }()
    
    let deviceName: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)

        return label
    }()
    
    let deleteButton: UIButton = {
        let uiButton = UIButton()
        uiButton.tintColor = UIColor.red
        uiButton.setImage(UIImage(systemName: "minus.circle"), for: UIControl.State.normal)
        return uiButton
    }()
}

extension TrustedDeviceCollectionViewCell {
    public func configure(with trustedDevice: TrustedDevice) {
        id.text = trustedDevice.id
        
        ip.text = trustedDevice.metadata.ip
        ip.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(ip)
        
        operatingSystem.text = trustedDevice.metadata.operatingSystem
        operatingSystem.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(operatingSystem)
        
        deviceClass.text = trustedDevice.metadata.deviceClass
        deviceClass.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(deviceClass)
        
        deviceName.text = trustedDevice.metadata.deviceName
        deviceName.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(deviceName)
        
        createdAt.text = trustedDevice.createdAt.components(separatedBy: "T")[0]
        createdAt.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(createdAt)
        
        deleteButton.frame = CGRect(x: contentView.frame.width - 20, y: 0, width: 20, height: 20)
        deleteButton.addTarget(self, action: #selector(deleteTrustedDeviceButtonTapped), for: UIControl.Event.touchUpInside)
        contentView.addSubview(deleteButton)
        
        let fontSize = contentView.frame.size.width < 330 ? 6.0 : 9.0
        createdAt.font = UIFont.preferredFont(forTextStyle: .body).withSize(fontSize)
        ip.font = UIFont.preferredFont(forTextStyle: .body).withSize(fontSize)
        operatingSystem.font = UIFont.preferredFont(forTextStyle: .body).withSize(fontSize)
        deviceClass.font = UIFont.preferredFont(forTextStyle: .body).withSize(fontSize)
        deviceName.font = UIFont.preferredFont(forTextStyle: .body).withSize(fontSize)
        
        
        let spacing = CGFloat((contentView.frame.width/6.5))
    
        NSLayoutConstraint.activate([
            ip.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            operatingSystem.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 1.2 * spacing),
            deviceName.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2 * spacing),
            deviceClass.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 3.5 * spacing),
            createdAt.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4.2 * spacing),
        ])
    }
    @IBAction func deleteTrustedDeviceButtonTapped() -> Void {
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }
        guard let deviceId = id.text else {
            print("identifier cannot be nil")
            return
        }
        
        let alert = UIAlertController(title: "Remove trusted device", message: "Are you sure you want to remove the trusted device ?", preferredStyle: .alert)
        
        let cancelAction = UIAlertAction(title: "No", style: .cancel) { _ in
                return
        }
        let approveRemove = UIAlertAction(title: "Yes", style: .default) { _ in
            AppDelegate().reachfive.mfaDelete(trustedDeviceId: deviceId, authToken: authToken)
                .onSuccess { _ in
                    self.contentView.removeFromSuperview()
                }
        }
        alert.addAction(cancelAction)
        alert.addAction(approveRemove)
        self.window?.rootViewController?.present(alert, animated: true)
    }
}

class CredentialCollectionViewCell: UICollectionViewListCell {
    static let identifier = "CredentialCollectionViewCell"

    let id: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        
        return label
    }()
    
    let createdAt: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)

        return label
    }()
    
    let deleteButton: UIButton = {
        let uiButton = UIButton()
        uiButton.tintColor = UIColor.red
        uiButton.setImage(UIImage(systemName: "minus.circle"), for: UIControl.State.normal)
        return uiButton
    }()
}

extension CredentialCollectionViewCell {
    public func configure(with credential: MfaCredential) {
        id.text = credential.identifier
        id.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(id)

        createdAt.text = credential.createdAt.components(separatedBy: ".")[0]
        createdAt.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(createdAt)
        
        deleteButton.frame = CGRect(x: contentView.frame.width - 20, y: 0, width: 20, height: 20)
        deleteButton.addTarget(self, action: #selector(deleteCredentialButtonTapped), for: UIControl.Event.touchUpInside)
        contentView.addSubview(deleteButton)
        
        let fontSize = contentView.frame.size.width < 330 ? 12.0 : 15.0
        id.font = UIFont.preferredFont(forTextStyle: .body).withSize(fontSize)
        createdAt.font = UIFont.preferredFont(forTextStyle: .body).withSize(fontSize)

        let spacing = CGFloat((contentView.frame.width/2.5))
    
        NSLayoutConstraint.activate([
            id.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            createdAt.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            deleteButton.leadingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 20)
        ])
    }
    @IBAction func deleteCredentialButtonTapped() -> Void {
        guard let authToken = AppDelegate.storage.getToken() else {
            print("not logged in")
            return
        }
        guard let identifier = id.text else {
            print("identifier cannot be nil")
            return
        }
        
        let alert = UIAlertController(title: "Remove identifier \(identifier)", message: "Are you sure you want to remove the identifier ?", preferredStyle: .alert)
        
        let cancelAction = UIAlertAction(title: "No", style: .cancel) { _ in
                return
        }
        let approveRemove = UIAlertAction(title: "Yes", style: .default) { _ in
            if(identifier.contains("@")) {
                AppDelegate.reachfive().mfaDeleteCredential(authToken: authToken)
                    .onSuccess { _ in
                        self.contentView.removeFromSuperview()
                    }
            } else {
                AppDelegate.reachfive()
                    .mfaDeleteCredential(identifier, authToken: authToken)
                    .onSuccess { _ in
                        self.contentView.removeFromSuperview()
                    }
            }
        }
        alert.addAction(cancelAction)
        alert.addAction(approveRemove)
        self.window?.rootViewController?.present(alert, animated: true)
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

class TitleSupplementaryView: UICollectionReusableView {
    let label = UILabel()
    static let reuseIdentifier = "title-supplementary-reuse-identifier"

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

extension TitleSupplementaryView {
    func configure() {
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        let inset = CGFloat(10)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            label.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ])
        label.font = UIFont.preferredFont(forTextStyle: .title3)
    }
}
