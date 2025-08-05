import UIKit
import os.log

/// A reusable view that displays the key-value pairs of a decoded JWT payload in a structured and readable format.
class DecodedTokenView: UIView {
    
    // MARK: - IBOutlets for Value Labels
    
    @IBOutlet weak var issLabel: UILabel!
    @IBOutlet weak var subLabel: UILabel!
    @IBOutlet weak var audLabel: UILabel!
    @IBOutlet weak var expLabel: UILabel!
    @IBOutlet weak var iatLabel: UILabel!
    @IBOutlet weak var jtiLabel: UILabel!
    @IBOutlet weak var amrLabel: UILabel!
    @IBOutlet weak var scopeLabel: UILabel!
    @IBOutlet weak var enforcesScopeLabel: UILabel!
    @IBOutlet weak var clientIdLabel: UILabel!
    @IBOutlet weak var authTimeLabel: UILabel!
    @IBOutlet weak var azpLabel: UILabel!
    
    // MARK: - IBOutlets for Container Stack Views
    
    @IBOutlet weak var issStackView: UIStackView!
    @IBOutlet weak var subStackView: UIStackView!
    @IBOutlet weak var audStackView: UIStackView!
    @IBOutlet weak var expStackView: UIStackView!
    @IBOutlet weak var iatStackView: UIStackView!
    @IBOutlet weak var jtiStackView: UIStackView!
    @IBOutlet weak var amrStackView: UIStackView!
    @IBOutlet weak var scopeStackView: UIStackView!
    @IBOutlet weak var enforcesScopeStackView: UIStackView!
    @IBOutlet weak var clientIdStackView: UIStackView!
    @IBOutlet weak var authTimeStackView: UIStackView!
    @IBOutlet weak var azpStackView: UIStackView!
    
    // MARK: - Configuration

    /// Configures the view with a dictionary representing the JWT payload.
    /// It populates the corresponding labels and hides stack views for fields that are not present.
    /// - Parameter payload: A dictionary containing the decoded token data.
    func configure(with payload: [String: Any]) {
        // A helper to set text on a label and manage the visibility of its container stack view.
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
            if let timestamp = timestamp {
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
        guard let payload = payload, !payload.isEmpty else { return nil }
        
        guard let view = Bundle.main.loadNibNamed("DecodedTokenView", owner: nil, options: nil)?.first as? DecodedTokenView else {
            return nil
        }
        
        view.configure(with: payload)
        return view
    }
}
