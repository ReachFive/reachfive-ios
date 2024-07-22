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
    
    //TODO return a future like mfaStart or directly update the profile info here
    func addPhoneNumber(shouldReplaceExisting: Bool, authToken: AuthToken) {
        let titre = if shouldReplaceExisting { "Updated phone number" } else { "New Phone Number" }
        let alert = UIAlertController(title: titre, message: "Please enter a phone number", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = titre
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        let submitPhoneNumber = UIAlertAction(title: "submit", style: .default) { _ in
            guard let phoneNumber = alert.textFields?[0].text else {
                //TODO alerte
                print("Phone number cannot be empty")
                return
            }
            AppDelegate.reachfive()
                .updatePhoneNumber(authToken: authToken, phoneNumber: phoneNumber)
                .onSuccess { profile in
                    return self.present(AppDelegate.createAlert(title: titre, message: "Success"), animated: true)
                }
                .onFailure { error in
                    self.present(AppDelegate.createAlert(title: titre, message: "Error: \(error.message())"), animated: true)
                }
        }
        alert.addAction(cancelAction)
        alert.addAction(submitPhoneNumber)
        present(alert, animated: true)
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "ToDisplayCell", for: indexPath)
        
        var content = cell.defaultContentConfiguration()
        content.text = self.propertiesToDisplay[indexPath.row].name
        content.secondaryText = self.propertiesToDisplay[indexPath.row].value
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
        }
        if let valeur = field.value {
            let copy = UIAction(title: "Copy", image: UIImage(systemName: "clipboard")) { action in
                UIPasteboard.general.string = valeur
            }
            children.append(copy)
            
            // MFA registering button
            if (self.mfaRegistrationAvailable.contains(field.name)) {
                let credential: Credential = switch field.name {
                case "Email": .Email()
                default: .PhoneNumber(valeur)
                }
                
                let mfaRegister = UIAction(title: "Enroll your \(credential.credentialType) as MFA", image: UIImage(systemName: "key")) { action in
                    let mfaAction = MfaAction(presentationAnchor: self)
                    mfaAction.mfaStart(registering: credential, authToken: token)
                        .onSuccess { _ in
                            self.fetchProfile()
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

