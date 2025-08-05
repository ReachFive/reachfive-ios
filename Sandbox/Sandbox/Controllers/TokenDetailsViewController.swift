import UIKit
import Reach5
import os.log

class TokenDetailsViewController: UIViewController {
    var authToken: AuthToken?

    // MARK: - IBOutlets for Raw Token Values

    @IBOutlet weak var idTokenLabel: UILabel!
    @IBOutlet weak var accessTokenLabel: UILabel!
    @IBOutlet weak var refreshTokenLabel: UILabel!
    @IBOutlet weak var tokenTypeLabel: UILabel!
    @IBOutlet weak var expiresInLabel: UILabel!

    // MARK: - IBOutlets for Decoded Token Views
    
    // These container views will hold the dynamically created DecodedTokenView instances.
    // Please add these UIStackViews in your storyboard.
    @IBOutlet weak var idTokenDecodedContainer: UIStackView!
    @IBOutlet weak var accessTokenDecodedContainer: UIStackView!
    @IBOutlet weak var refreshTokenDecodedContainer: UIStackView!

    // MARK: - UIViewController Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Token Details"
        configureWithAuthToken()
        setupCopyableLabels()
    }

    // MARK: - Token Configuration

    /// Configures the view with both raw and decoded token details.
    private func configureWithAuthToken() {
        guard let authToken = authToken else { return }
        
        // Display the raw token strings.
        idTokenLabel.text = authToken.idToken ?? "N/A"
        accessTokenLabel.text = authToken.accessToken
        refreshTokenLabel.text = authToken.refreshToken ?? "N/A"
        tokenTypeLabel.text = authToken.tokenType ?? "N/A"
        expiresInLabel.text = authToken.expiresIn.map { String($0) } ?? "N/A"

        // Clear any previously added decoded views to prevent duplication.
        clearDecodedViews()

        // Decode and display the ID token payload.
        if let idTokenPayload = decodeTokenPayload(authToken.idToken),
           let decodedView = DecodedTokenView.create(with: idTokenPayload) {
            idTokenDecodedContainer.addArrangedSubview(decodedView)
        }
        
        // Decode and display the access token payload.
        if let accessTokenPayload = decodeTokenPayload(authToken.accessToken),
           let decodedView = DecodedTokenView.create(with: accessTokenPayload) {
            accessTokenDecodedContainer.addArrangedSubview(decodedView)
        }

        // Decode and display the refresh token payload, if it exists.
        if let refreshTokenPayload = decodeTokenPayload(authToken.refreshToken),
           let decodedView = DecodedTokenView.create(with: refreshTokenPayload) {
            refreshTokenDecodedContainer.addArrangedSubview(decodedView)
        }
    }
    
    /// Removes all subviews from the decoded token container stack views.
    private func clearDecodedViews() {
        idTokenDecodedContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        accessTokenDecodedContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        refreshTokenDecodedContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    /// Decodes a JWT string into a dictionary.
    /// - Parameter token: The JWT string.
    /// - Returns: A dictionary representing the token's payload, or `nil` on failure.
    private func decodeTokenPayload(_ token: String?) -> [String: Any]? {
        guard let token = token else { return nil }
        
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else {
            if #available(iOS 14.0, *) {
                Logger.auth.error("Invalid token format: \(token)")
            }
            return nil
        }

        // Pad the base64 string as needed before decoding.
        var base64String = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64String.count % 4
        if padding > 0 {
            base64String += String(repeating: "=", count: 4 - padding)
        }
        
        guard let payloadData = Data(base64Encoded: base64String) else {
            if #available(iOS 14.0, *) {
                Logger.auth.error("Failed to decode base64 payload from token: \(token)")
            }
            return nil
        }

        return try? JSONSerialization.jsonObject(with: payloadData, options: []) as? [String: Any]
    }

    // MARK: - UI Interaction

    /// Sets up tap gestures to allow copying of the raw token values.
    private func setupCopyableLabels() {
        [idTokenLabel, accessTokenLabel, refreshTokenLabel].forEach { label in
            guard let label = label else { return }
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(labelTapped(_:)))
            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(tapGesture)
        }
    }

    /// Handles tap-to-copy functionality for labels.
    @objc private func labelTapped(_ sender: UITapGestureRecognizer) {
        guard let label = sender.view as? UILabel, let text = label.text, text != "N/A" else { return }

        UIPasteboard.general.string = text

        let originalText = label.text
        label.text = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            label.text = originalText
        }
    }

    /// Revokes the tokens after user confirmation.
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
