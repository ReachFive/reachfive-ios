import Foundation
import UIKit
import Reach5

struct Field {
    let name: String
    let value: String?
}

// TODO:
// - remove enroll MFA identifier in menu when the identifier has already been enrolled. Requires listMfaCredentials
// - refaire la présentation avec une Collection View : https://developer.apple.com/videos/play/wwdc2019/215
extension ProfileController {

    func format(date: Int) -> String {
        let lastLogin = Date(timeIntervalSince1970: TimeInterval(date / 1000))
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        dateFormatter.locale = Locale(identifier: "en_GB")
        return dateFormatter.string(from: lastLogin)
    }

    func emailVerificationCode(authToken: AuthToken, email: String) async {
        do {
            let emailVerificationResponse = try await AppDelegate.reachfive().sendEmailVerification(authToken: authToken)

            switch emailVerificationResponse {

            case EmailVerificationResponse.Success:
                self.presentAlert(title: "Email verification", message: "Success")
                self.fetchProfile()

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
                            self.fetchProfile()
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
    }
}

extension ProfileController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return propertiesToDisplay.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let field = self.propertiesToDisplay[indexPath.row]
        return tableView.dequeueDefaultReusableCell(withIdentifier: "ToDisplayCell", for: indexPath, text: field.name, secondaryText: field.value)
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let field = self.propertiesToDisplay[indexPath.row]
        guard let token = self.authToken else {
            return nil
        }

        var children: [UIMenuElement] = []
        if field.name == "Phone Number" {
            let title = if field.value == nil { "Add" } else { "Update" }
            let updatePhone = UIAction(title: title, image: UIImage(systemName: "phone.badge.plus.fill")) { action in
                self.addPhoneNumber(shouldReplaceExisting: field.value != nil, authToken: token)
            }
            children.append(updatePhone)
            if field.value != nil {
                let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "minus.circle.fill")) { action in
                    Task {
                        await self.updateProfileField(titre: "Delete Phone number", authToken: token, update: ProfileUpdate(phoneNumber: .Delete))
                    }
                }
                children.append(deleteAction)
            }
        }

        func updateAndDeleteField(name: String, icon: String, updater: @escaping (Diff<String>) -> ProfileUpdate) {
            if field.name == name {
                let title = if field.value == nil { "Add" } else { "Update" }
                let updateAction = UIAction(title: title, image: UIImage(systemName: icon)) { action in
                    self.popupUpdateProfileField(fieldName: name, authToken: token) {
                        updater(.Update($0))
                    }
                }
                children.append(updateAction)
                if field.value != nil {
                    let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "minus.circle.fill")) { action in
                        Task {
                            await self.updateProfileField(titre: "Delete \(name)", authToken: token, update: updater(.Delete))
                        }
                    }
                    children.append(deleteAction)
                }
            }
        }

        if field.name == "Email" {
            if field.value == nil {
                let updateAction = UIAction(title: "Add", image: UIImage(systemName: "at.badge.plus")) { action in
                    self.popupUpdateProfileField(fieldName: "Email", authToken: token) {
                        ProfileUpdate(email: .Update($0))
                    }
                }
                children.append(updateAction)
            }
        }

        updateAndDeleteField(name: "Custom Identifier", icon: "person.fill.badge.plus") {
            ProfileUpdate(customIdentifier: $0)
        }

        updateAndDeleteField(name: "Given Name", icon: "person.text.rectangle.fill") {
            ProfileUpdate(givenName: $0)
        }

        updateAndDeleteField(name: "Family Name", icon: "person.text.rectangle.fill") {
            ProfileUpdate(familyName: $0)
        }

        if let valeur = field.value {
            let copy = UIAction(title: "Copy", image: UIImage(systemName: "clipboard")) { _ in
                UIPasteboard.general.string = valeur
            }
            children.append(copy)


            if (field.name == "Email") {
                if (field.value != nil && field.value!.contains(" ✘")) {
                    let email = field.value!.split(separator: " ").first
                    let emailVerification = UIAction(title: "Verify Email", image: UIImage(systemName: "lock")) { _ in
                        Task {
                            await self.emailVerificationCode(authToken: token, email: email!.base)
                        }
                    }
                    children.append(emailVerification)
                }

            }

            // MFA registering button
            if (self.mfaRegistrationAvailable.contains(field.name)) {
                let credential: Credential = switch field.name {
                case "Email": .Email()
                default: .PhoneNumber(valeur)
                }

                let mfaRegister = UIAction(title: "Enroll your \(credential.credentialType) as MFA", image: UIImage(systemName: "key")) { _ in
                    let mfaAction = MfaAction(presentationAnchor: self)
                    Task {
                        do {
                            let _ = try await mfaAction.mfaStart(registering: credential, authToken: token)
                            await self.fetchProfile()
                        } catch {
                            self.presentErrorAlert(title: "Enroll failed", error)
                        }
                    }
                }

                children.append(mfaRegister)
            }
        }

        // Do not return an empty menu otherwise on the UI the table will behave as if it about to display a menu but there is nothing to display
        if children.isEmpty {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { actions -> UIMenu? in
            return UIMenu(title: "Actions", children: children)
        }
    }
}

