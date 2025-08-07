import UIKit
import Reach5

extension UIViewController {
    func handleAuthToken(errorMessage: String = "Login failed", _ body: () async throws -> AuthToken) async {
        do {
            let authToken = try await body()
            goToProfile(authToken)
        } catch {
            presentErrorAlert(title: errorMessage, error)
        }
    }

    @MainActor
    func goToProfile(_ authToken: AuthToken) {
        AppDelegate.storage.setToken(authToken)

        if let tabBarController = storyboard?.instantiateViewController(withIdentifier: "Tabs") as? UITabBarController {
            tabBarController.selectedIndex = 2 // profile is third from left
            navigationController?.pushViewController(tabBarController, animated: true)
        }
    }

    func handleLoginFlow(errorMessage: String = "Login failed", _ body: () async throws -> LoginFlow) async {
        do {
            let flow = try await body()
            flowTheLogin(flow)
        } catch {
            presentErrorAlert(title: errorMessage, error)
        }
    }

    func flowTheLogin(_ flow: LoginFlow) {
        switch flow {
        case .AchievedLogin(let authToken):
            goToProfile(authToken)
        case .OngoingStepUp(let token, let availableMfaCredentialItemTypes):
            let selectMfaAuthTypeAlert = UIAlertController(title: "Select MFA", message: "Select MFA auth type", preferredStyle: UIAlertController.Style.alert)
            var lastAction: UIAlertAction? = nil
            for type in availableMfaCredentialItemTypes {
                let action = createSelectMfaAuthTypeAction(type: type, stepUpToken: token)
                selectMfaAuthTypeAlert.addAction(action)
                lastAction = action
            }
            selectMfaAuthTypeAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            selectMfaAuthTypeAlert.preferredAction = lastAction
           Task { @MainActor in
                present(selectMfaAuthTypeAlert, animated: true)
           }
        }
    }

    @MainActor
    func showToast(message: String, seconds: Double) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + seconds) {
            alert.dismiss(animated: true)
        }
    }

    private func createSelectMfaAuthTypeAction(type: MfaCredentialItemType, stepUpToken: String) -> UIAlertAction {
        return UIAlertAction(title: type.rawValue, style: .default) { _ in
            Task {
                await self.handleAuthToken {
                    let resp = try await AppDelegate.reachfive().mfaStart(stepUp: .LoginFlow(authType: type, stepUpToken: stepUpToken))
                    return try await self.handleStartVerificationCode(resp, authType: type)
                }
            }
        }
    }

    private func handleStartVerificationCode(_ resp: ContinueStepUp, authType: MfaCredentialItemType) async throws -> AuthToken {
        return try await withCheckedThrowingContinuation { continuation in

            let alert = UIAlertController(title: "Verification code", message: "Please enter the verification code you got by \(authType)", preferredStyle: .alert)
            alert.addTextField { textField in
                textField.placeholder = "Verification code"
                textField.keyboardType = .numberPad
                textField.textContentType = .oneTimeCode
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(throwing: ReachFiveError.AuthCanceled)
            }
            func submitVerificationCode(withTrustDevice trustDevice: Bool?) {
                Task {
                    guard let verificationCode = alert.textFields?[0].text, !verificationCode.isEmpty else {
                        continuation.resume(throwing: ReachFiveError.AuthCanceled)
                        return
                    }
                    continuation.resume {
                        try await resp.verify(code: verificationCode, trustDevice: trustDevice)
                    }
                }
            }

            let submitVerificationTrustDevice = UIAlertAction(title: "Trust device", style: .default) { _ in
                submitVerificationCode(withTrustDevice: true)
            }
            let submitVerificationNoTrustDevice = UIAlertAction(title: "Don't trust device", style: .default) { _ in
                submitVerificationCode(withTrustDevice: false)
            }
            let submitVerificationWithoutRba = UIAlertAction(title: "Ignore RBA", style: .default) { _ in
                submitVerificationCode(withTrustDevice: nil)
            }
            alert.addAction(cancelAction)
            alert.addAction(submitVerificationTrustDevice)
            alert.addAction(submitVerificationNoTrustDevice)
            alert.addAction(submitVerificationWithoutRba)
            present(alert, animated: true)
        }
    }

    @MainActor
    func presentAlert(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: UIAlertController.Style.alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default))
        self.present(alert, animated: true)
    }

    func presentErrorAlert(title: String, _ error: Error) {
        switch error {
        case ReachFiveError.AuthCanceled: return
        default:
            self.presentAlert(title: title, message: "Error: \(error.localizedDescription)")
        }
    }
}
