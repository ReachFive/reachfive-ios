import UIKit
import Reach5

class TokenDetailsViewController: UIViewController {
    var authToken: AuthToken?

    @IBOutlet weak var idTokenLabel: UILabel!
    @IBOutlet weak var accessTokenLabel: UILabel!
    @IBOutlet weak var refreshTokenLabel: UILabel!
    @IBOutlet weak var tokenTypeLabel: UILabel!
    @IBOutlet weak var expiresInLabel: UILabel!

    @IBOutlet weak var decodeRefreshTokenButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Token Details"
        configureWithAuthToken()
        setupCopyableLabels()
    }

    private func configureWithAuthToken() {
        guard let authToken = authToken else { return }
        idTokenLabel.text = authToken.idToken ?? "N/A"
        accessTokenLabel.text = authToken.accessToken
        refreshTokenLabel.text = authToken.refreshToken ?? "N/A"
        tokenTypeLabel.text = authToken.tokenType ?? "N/A"
        expiresInLabel.text = authToken.expiresIn.map { String($0) } ?? "N/A"

        decodeRefreshTokenButton.isHidden = authToken.refreshToken == nil
    }

    private func setupCopyableLabels() {
        [idTokenLabel, accessTokenLabel, refreshTokenLabel].forEach { label in
            guard let label = label else { return }
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(labelTapped(_:)))
            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(tapGesture)
        }
    }

    @objc private func labelTapped(_ sender: UITapGestureRecognizer) {
        guard let label = sender.view as? UILabel, let text = label.text, text != "N/A" else { return }

        UIPasteboard.general.string = text

        let originalText = label.text
        label.text = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            label.text = originalText
        }
    }

    @IBAction func decodeAccessTokenTapped(_ sender: UIButton) {
        guard let token = authToken?.accessToken else { return }
        decode(token: token)
    }

    @IBAction func decodeRefreshTokenTapped(_ sender: UIButton) {
        guard let token = authToken?.refreshToken else { return }
        decode(token: token)
    }

    private func decode(token: String) {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else {
            presentAlert(title: "Invalid Token", message: "The token is not a valid JWT.")
            return
        }

        let payloadData = Data(base64Encoded: segments[1]) ?? Data()

        if let json = try? JSONSerialization.jsonObject(with: payloadData, options: []),
           let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: data, encoding: .utf8) {
            presentAlert(title: "Decoded Token", message: prettyString)
        } else {
            presentAlert(title: "Invalid Payload", message: "The token payload is not valid JSON.")
        }
    }

    @IBAction func revokeTokenTapped(_ sender: UIButton) {
        guard let authToken = authToken else { return }

        let alert = UIAlertController(title: "Revoke Token", message: "Are you sure you want to revoke the tokens? This action cannot be undone.", preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let revokeAction = UIAlertAction(title: "Revoke", style: .destructive) { _ in
            Task {
                do {
                    try await AppDelegate.reachfive().revokeToken(authToken: authToken, tokenType: .accessToken)
                    if authToken.refreshToken != nil {
                        try await AppDelegate.reachfive().revokeToken(authToken: authToken, tokenType: .refreshToken)
                    }
                    AppDelegate.storage.removeToken()
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    self.presentErrorAlert(title: "Revocation Failed", error)
                }
            }
        }
        alert.addAction(cancelAction)
        alert.addAction(revokeAction)
        present(alert, animated: true)
    }
}
