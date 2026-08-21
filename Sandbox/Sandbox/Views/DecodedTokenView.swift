import os.log
import UIKit

/// A reusable view that displays the key-value pairs of a decoded JWT payload in a structured and readable format.
class DecodedTokenView: UIView {
    // MARK: - IBOutlets for Value Labels

    @IBOutlet var issLabel: UILabel!
    @IBOutlet var subLabel: UILabel!
    @IBOutlet var audLabel: UILabel!
    @IBOutlet var expLabel: UILabel!
    @IBOutlet var iatLabel: UILabel!
    @IBOutlet var jtiLabel: UILabel!
    @IBOutlet var amrLabel: UILabel!
    @IBOutlet var scopeLabel: UILabel!
    @IBOutlet var enforcesScopeLabel: UILabel!
    @IBOutlet var clientIdLabel: UILabel!
    @IBOutlet var authTimeLabel: UILabel!
    @IBOutlet var azpLabel: UILabel!

    // MARK: - IBOutlets for Container Stack Views

    @IBOutlet var issStackView: UIStackView!
    @IBOutlet var subStackView: UIStackView!
    @IBOutlet var audStackView: UIStackView!
    @IBOutlet var expStackView: UIStackView!
    @IBOutlet var iatStackView: UIStackView!
    @IBOutlet var jtiStackView: UIStackView!
    @IBOutlet var amrStackView: UIStackView!
    @IBOutlet var scopeStackView: UIStackView!
    @IBOutlet var enforcesScopeStackView: UIStackView!
    @IBOutlet var clientIdStackView: UIStackView!
    @IBOutlet var authTimeStackView: UIStackView!
    @IBOutlet var azpStackView: UIStackView!

    // MARK: - Configuration

    /// Configures the view with a dictionary representing the JWT payload.
    /// It populates the corresponding labels and hides stack views for fields that are not present.
    /// - Parameter payload: A dictionary containing the decoded token data.
    func configure(with payload: [String: Any]) {
        /// A helper to set text on a label and manage the visibility of its container stack view.
        func setText(for label: UILabel, stackView: UIStackView, value: Any?) {
            if let value {
                label.text = String(describing: value)
                stackView.isHidden = false
            } else {
                stackView.isHidden = true
            }
        }

        // A helper for date formatting.
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .long

        func setDate(for label: UILabel, stackView: UIStackView, timestamp: TimeInterval?) {
            if let timestamp {
                let date = Date(timeIntervalSince1970: timestamp)
                label.text = "\(dateFormatter.string(from: date)) (\(Int(timestamp)))"
                stackView.isHidden = false
            } else {
                stackView.isHidden = true
            }
        }

        // Populate each field.
        setText(for: issLabel, stackView: issStackView, value: payload["iss"])
        setText(for: subLabel, stackView: subStackView, value: payload["sub"])
        setText(for: jtiLabel, stackView: jtiStackView, value: payload["jti"])
        setText(for: clientIdLabel, stackView: clientIdStackView, value: payload["client_id"])
        setText(for: azpLabel, stackView: azpStackView, value: payload["azp"])
        setText(for: enforcesScopeLabel, stackView: enforcesScopeStackView, value: (payload["enforces_scope"] as? Int == 1))

        // Handle audience, which can be a string or an array of strings.
        if let aud = payload["aud"] as? [String] {
            setText(for: audLabel, stackView: audStackView, value: aud.joined(separator: ", "))
        } else {
            setText(for: audLabel, stackView: audStackView, value: payload["aud"])
        }

        // Handle AMR, which is an array of strings.
        if let amr = payload["amr"] as? [String] {
            setText(for: amrLabel, stackView: amrStackView, value: amr.joined(separator: ", "))
        } else {
            amrStackView.isHidden = true
        }

        // Handle scope, which can be an array of strings or a single space-separated string.
        if let scopeArray = payload["scope"] as? [String] {
            setText(for: scopeLabel, stackView: scopeStackView, value: scopeArray.joined(separator: ", "))
        } else if let scopeString = payload["scope"] as? String {
            setText(for: scopeLabel, stackView: scopeStackView, value: scopeString.replacingOccurrences(of: " ", with: ", "))
        } else {
            scopeStackView.isHidden = true
        }

        // Handle timestamp fields.
        setDate(for: expLabel, stackView: expStackView, timestamp: payload["exp"] as? TimeInterval)
        setDate(for: iatLabel, stackView: iatStackView, timestamp: payload["iat"] as? TimeInterval)
        setDate(for: authTimeLabel, stackView: authTimeStackView, timestamp: payload["auth_time"] as? TimeInterval)
    }

    // MARK: - Factory Method

    /// Creates and configures an instance of `DecodedTokenView` from its XIB.
    /// - Parameter payload: The token payload to display.
    /// - Returns: A configured `DecodedTokenView` instance, or `nil` if the payload is empty or the XIB cannot be loaded.
    static func create(with payload: [String: Any]?) -> DecodedTokenView? {
        guard let payload, !payload.isEmpty else { return nil }

        guard let view = Bundle.main.loadNibNamed("DecodedTokenView", owner: nil, options: nil)?.first as? DecodedTokenView else {
            return nil
        }

        view.configure(with: payload)
        return view
    }
}
