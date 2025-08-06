import Foundation
import UIKit
import Reach5

struct Field {
    let name: String
    let value: String?
}

enum Section: Int, CaseIterable {
    case ContactInformation
    case ProfileInformation
    case Security
    case Token
    case Metadata
    case Logout
}

enum SecurityRows: Int, CaseIterable {
    //TODO: case Password // show if there is one, and able to add/edit
    case Passkeys
    case TrustedDevices
    case Addresses
    case CustomFields
    case Consents
}

extension ProfileController {

    static func format(date: Int) -> String {
        let lastLogin = Date(timeIntervalSince1970: TimeInterval(date / 1000))
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        dateFormatter.locale = Locale(identifier: "en_GB")
        return dateFormatter.string(from: lastLogin)
    }

    //TODO: avec les actions
    func emailVerificationCode(authToken: AuthToken, email: String) async {
        do {
            let emailVerificationResponse = try await AppDelegate.reachfive().sendEmailVerification(authToken: authToken)

            switch emailVerificationResponse {

            case EmailVerificationResponse.Success:
                self.presentAlert(title: "Email verification", message: "Success")
                self.fetchData() //TODO: recharger seulement la section

            case let EmailVerificationResponse.VerificationNeeded(continueEmailVerification):
                let alert = UIAlertController(title: "Email verification", message: "Please enter the code you received by Email", preferredStyle: .alert)
                alert.addTextField { textField in
                    textField.placeholder = "Verification code"
                    textField.keyboardType = .numberPad
                    textField.textContentType = .oneTimeCode
                }
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
                let submitVerificationCode = UIAlertAction(title: "Submit", style: .default) { _ in
                    Task {
                        guard let verificationCode = alert.textFields?[0].text else {
                            print("VerificationCode cannot be empty")
                            return
                        }
                        do {
                            let _ = try await continueEmailVerification.verify(code: verificationCode, email: email)
                            self.presentAlert(title: "Email verification", message: "Success")
                            self.fetchData() //TODO: recharger seulement la section
                        } catch {
                            self.presentErrorAlert(title: "Email verification failed", error)
                        }
                    }
                }
                alert.addAction(cancelAction)
                alert.addAction(submitVerificationCode)
                alert.preferredAction = submitVerificationCode
                self.present(alert, animated: true)
            }

        } catch {
            self.presentErrorAlert(title: "Email verification failed", error)
        }
    }

    func addPhoneNumber(shouldReplaceExisting: Bool, authToken: AuthToken) {
        let titre = if shouldReplaceExisting { "Updated phone number" } else { "New Phone Number" }
        let alert = UIAlertController(title: titre, message: "Please enter a phone number", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = titre
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let submitPhoneNumber = UIAlertAction(title: "Submit", style: .default) { _ in
            Task {
                guard let phoneNumber = alert.textFields?[0].text else {
                    print("Phone number cannot be empty")
                    return
                }
                do {
                    let profile = try await AppDelegate.reachfive().updatePhoneNumber(authToken: authToken, phoneNumber: phoneNumber)
                    self.reaload(updated: profile)
                } catch {
                    self.presentErrorAlert(title: "\(titre) failed", error)
                }
            }
        }
        alert.addAction(cancelAction)
        alert.addAction(submitPhoneNumber)
        present(alert, animated: true)
    }

    func popupUpdateProfileField(fieldName: String, authToken: AuthToken, updater: @escaping (String) -> ProfileUpdate) {
        let alert = UIAlertController(title: fieldName, message: "Please enter a \(fieldName)", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = fieldName
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let submitAction = UIAlertAction(title: "Submit", style: .default) { _ in
            Task {
                guard let newValue = alert.textFields?[0].text, !newValue.isEmpty else {
                    print("\(fieldName) cannot be empty")
                    return
                }
                await self.updateProfileField(titre: fieldName, authToken: authToken, update: updater(newValue))
            }
        }
        alert.addAction(cancelAction)
        alert.addAction(submitAction)
        present(alert, animated: true)
    }

    func updateProfileField(titre: String, authToken: AuthToken, update: ProfileUpdate) async {
        do {
            let profile = try await AppDelegate.reachfive().updateProfile(authToken: authToken, profileUpdate: update)
            reaload(updated: profile)
        } catch {
            self.presentErrorAlert(title: "\(titre) failed", error)
        }
    }

    @MainActor
    func reaload(updated profile: Profile) {
        self.profile = profile
        self.profileData.reloadData()
    }
}

extension ProfileController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let section = Section(rawValue: indexPath.section) else { return }

        if section == .Token {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            if let tokenDetailsVC = storyboard.instantiateViewController(withIdentifier: "TokenDetailsViewController") as? TokenDetailsViewController {
                tokenDetailsVC.authToken = self.authToken
                self.navigationController?.pushViewController(tokenDetailsVC, animated: true)
            }
        }
    }
}

extension ProfileController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            print("section not found")
            return 0 }
        print("found section")
        switch section {
        case .ContactInformation:
            let hasMfaPhoneNumber = mfaCredentials.contains { $0.type == .sms && $0.phoneNumber != profile.phoneNumber }
            return hasMfaPhoneNumber ? 3 : 2
        case .ProfileInformation: return editableFields.count // Editable fields
        case .Security: return SecurityRows.allCases.count
        case .Token: return 1
        case .Metadata: return metadataFields.count
        case .Logout: return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let section = Section(rawValue: indexPath.section) else {
            print("section not found")
return UITableViewCell() }
        switch section {
        case .ContactInformation: return contactInfoCell(for: indexPath)
        case .ProfileInformation: return editableProfileCell(for: indexPath)
        case .Security: return navigableCell(for: indexPath)
        case .Token: return tokenManagementCell(for: indexPath)
        case .Metadata: return metadataCell(for: indexPath)
        case .Logout: return logoutCell(for: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        guard let section = Section(rawValue: section) else {
            print("section not found")
            return "" }
        switch section {
        case .ContactInformation: return "Contact Information"
        case .ProfileInformation: return "Profile Information"
        case .Security: return "Security & Complex Data"
        case .Token: return "Token"
        case .Metadata: return "Metadata"
        case .Logout: return "Logout"
        }
    }

    private func contactInfoCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = profileData.dequeueReusableCell(withIdentifier: "ProfileContactInfoCell", for: indexPath) as! ProfileContactInfoCell

        switch indexPath.row {
        case 0:
            let isEnrolled = mfaCredentials.contains { $0.type == .email }
            cell.configure(fieldName: "Email", value: profile.email, isVerified: profile.emailVerified ?? false, isMfaEnrolled: isEnrolled, actions: emailActions())
        case 1:
            let isEnrolled = profile.phoneNumber != nil && mfaCredentials.contains { $0.phoneNumber == profile.phoneNumber }
            cell.configure(fieldName: "Phone Number", value: profile.phoneNumber, isVerified: profile.phoneNumberVerified ?? false, isMfaEnrolled: isEnrolled, actions: phoneNumberActions())
        case 2:
            if let mfaPhone = mfaCredentials.first(where: { $0.type == .sms && $0.phoneNumber != profile.phoneNumber }) {
                cell.configure(fieldName: "MFA Phone", value: mfaPhone.phoneNumber, isVerified: true, isMfaEnrolled: true, actions: mfaPhoneNumberActions(for: mfaPhone))
            }
        default:
            break
        }
        return cell
    }

    private func editableProfileCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = profileData.dequeueReusableCell(withIdentifier: "EditableProfileFieldCell", for: indexPath) as! EditableProfileFieldCell
        let field = editableFields[indexPath.row]
        let value = updatedProfile?[keyPath: field.path].value

        cell.configure(fieldName: field.name, value: value, isEditing: isEditMode)
        cell.onTextChanged = { [weak self] newValue in
            self?.updatedProfile?[keyPath: field.path] = .Update(newValue ?? "")
        }
        return cell
    }

    private func navigableCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = /*profileData.dequeueReusableCell(withIdentifier: "DisclosureCell") ??*/ UITableViewCell(style: .value1, reuseIdentifier: "DisclosureCell")
        
        guard let row = SecurityRows(rawValue: indexPath.row) else {
            return cell
        }

        cell.accessoryType = .disclosureIndicator
        switch row {
        case .Passkeys:
            cell.textLabel?.text = "Passkeys"
            cell.detailTextLabel?.text = "\(passkeys.count)"
        case .TrustedDevices:
            cell.textLabel?.text = "Trusted Devices"
            cell.accessoryType = .none
            switch trustedDevicesState {
            case .loading:
                cell.detailTextLabel?.text = "Loading..."
            case .loaded(let devices):
                cell.detailTextLabel?.text = "\(devices.count)"
                cell.accessoryType = .disclosureIndicator
            case .error(let message):
                cell.detailTextLabel?.text = message
            case .unavailable:
                cell.detailTextLabel?.text = "Not available"
            case .stepUpRequired:
                cell.detailTextLabel?.text = "Step-up required"
            }
        case .Addresses:
            cell.textLabel?.text = "Addresses"
            cell.detailTextLabel?.text = "\(profile.addresses?.count ?? 0)"
        case .CustomFields:
            cell.textLabel?.text = "Custom Fields"
            cell.detailTextLabel?.text = "\(profile.customFields?.count ?? 0)"
        case .Consents:
            cell.textLabel?.text = "Consents"
            cell.detailTextLabel?.text = "\(profile.consents?.count ?? 0)"
        }
        return cell
    }

    private func tokenManagementCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = /*profileData.dequeueReusableCell(withIdentifier: "DisclosureCell") ??*/ UITableViewCell(style: .default, reuseIdentifier: "DisclosureCell")
        cell.textLabel?.text = "View & Manage Token"
        cell.detailTextLabel?.text = ""
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func metadataCell(for indexPath: IndexPath) -> UITableViewCell {
        let field = metadataFields[indexPath.row]
        let cell = profileData.dequeueReusableCell(withIdentifier: "Value1Cell") ?? UITableViewCell(style: .value1, reuseIdentifier: "Value1Cell")
        cell.textLabel?.text = field.name
        cell.detailTextLabel?.text = field.valuef(profile) ?? "Not set"
        return cell
    }

    private func logoutCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = profileData.dequeueReusableCell(withIdentifier: "LogoutCell", for: indexPath) as! LogoutCell
        cell.onLogoutTapped = { [weak self] revoke, webLogout in
            self?.logoutAction(revoke: revoke, webLogout: webLogout)
        }
        cell.onRevokeInfoTapped = { [weak self] in
            self?.showRevokeTokenInfo()
        }
        cell.onWebLogoutInfoTapped = { [weak self] in
            self?.showWebLogoutInfo()
        }
        return cell
    }

    private func showRevokeTokenInfo() {
        presentAlert(title: "Revoke Tokens", message: "This option will invalidate all the refresh and access tokens associated with your account.")
    }

    private func showWebLogoutInfo() {
        presentAlert(title: "Web Logout", message: "This option open a browser window to log you out from the web session, clearing any cookies set in your browser.")
    }

//    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
//        let field = self.propertiesToDisplay[indexPath.row]
//        guard let token = self.authToken else {
//            return nil
//        }
//
//        var children: [UIMenuElement] = []
//        if field.name == "Phone Number" {
//            let title = if field.value == nil { "Add" } else { "Update" }
//            let updatePhone = UIAction(title: title, image: UIImage(systemName: "phone.badge.plus.fill")) { action in
//                self.addPhoneNumber(shouldReplaceExisting: field.value != nil, authToken: token)
//            }
//            children.append(updatePhone)
//            if field.value != nil {
//                //TODO: Vérifier le numéro de téléphone
//                let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "minus.circle.fill")) { action in
//                    Task {
//                        //TODO: Si la fonctionnalité SMS est activée, on ne peut pas utiliser cette méthode
//                        await self.updateProfileField(titre: "Delete Phone number", authToken: token, update: ProfileUpdate(phoneNumber: .Delete))
//                    }
//                }
//                children.append(deleteAction)
//            }
//        }
//
//        func updateAndDeleteField(name: String, icon: String, updater: @escaping (Diff<String>) -> ProfileUpdate) {
//            if field.name == name {
//                let title = if field.value == nil { "Add" } else { "Update" }
//                let updateAction = UIAction(title: title, image: UIImage(systemName: icon)) { action in
//                    self.popupUpdateProfileField(fieldName: name, authToken: token) {
//                        updater(.Update($0))
//                    }
//                }
//                children.append(updateAction)
//                if field.value != nil {
//                    let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "minus.circle.fill")) { action in
//                        Task {
//                            await self.updateProfileField(titre: "Delete \(name)", authToken: token, update: updater(.Delete))
//                        }
//                    }
//                    children.append(deleteAction)
//                }
//            }
//        }
//
//        if field.name == "Email" {
//            if field.value == nil {
//                let updateAction = UIAction(title: "Add", image: UIImage(systemName: "at.badge.plus")) { action in
//                    self.popupUpdateProfileField(fieldName: "Email", authToken: token) {
//                        ProfileUpdate(email: .Update($0))
//                    }
//                }
//                children.append(updateAction)
//            }
//        }
//
//        updateAndDeleteField(name: "Custom Identifier", icon: "person.fill.badge.plus") {
//            ProfileUpdate(customIdentifier: $0)
//        }
//
//        updateAndDeleteField(name: "Given Name", icon: "person.text.rectangle.fill") {
//            ProfileUpdate(givenName: $0)
//        }
//
//        updateAndDeleteField(name: "Family Name", icon: "person.text.rectangle.fill") {
//            ProfileUpdate(familyName: $0)
//        }
//
//        if let valeur = field.value {
//            let copy = UIAction(title: "Copy", image: UIImage(systemName: "clipboard")) { _ in
//                UIPasteboard.general.string = valeur
//            }
//            children.append(copy)
//
//
//            if (field.name == "Email") {
//                if (field.value != nil && field.value!.contains(" ✘")) {
//                    let email = field.value!.split(separator: " ").first
//                    let emailVerification = UIAction(title: "Verify Email", image: UIImage(systemName: "lock")) { _ in
//                        Task {
//                            await self.emailVerificationCode(authToken: token, email: email!.base)
//                        }
//                    }
//                    children.append(emailVerification)
//                }
//
//            }
//
//            // MFA registering button
//            if (self.mfaRegistrationAvailable.contains(field.name)) {
//                let credential: Credential = switch field.name {
//                case "Email": .Email()
//                default: .PhoneNumber(valeur)
//                }
//
//                let mfaRegister = UIAction(title: "Enroll your \(credential.credentialType) as MFA", image: UIImage(systemName: "key")) { _ in
//                    let mfaAction = MfaAction(presentationAnchor: self)
//                    Task {
//                        do {
//                            let _ = try await mfaAction.mfaStart(registering: credential, authToken: token)
//                            self.fetchData() //TODO: recharger seulement la section
//                        } catch {
//                            self.presentErrorAlert(title: "Enroll failed", error)
//                        }
//                    }
//                }
//
//                children.append(mfaRegister)
//            }
//        }
//
//        // Do not return an empty menu otherwise on the UI the table will behave as if it about to display a menu but there is nothing to display
//        if children.isEmpty {
//            return nil
//        }
//        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { actions -> UIMenu? in
//            return UIMenu(title: "Actions", children: children)
//        }
//    }
}
