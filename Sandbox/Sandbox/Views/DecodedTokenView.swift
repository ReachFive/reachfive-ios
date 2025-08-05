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
    
    // MARK: - IBOutlets for Container Stack Views
    
    @IBOutlet weak var issStackView: UIStackView!
    @IBOutlet weak var subStackView: UIStackView!
    @IBOutlet weak var audStackView: UIStackView!
    @IBOutlet weak var expStackView: UIStackView!
    @IBOutlet weak var iatStackView: UIStackView!
    @IBOutlet weak var jtiStackView: UIStackView!
    @IBOutlet weak var amrStackView: UIStackView!
    
    // MARK: - Configuration

    /// Configures the view with a dictionary representing the JWT payload.
    /// It populates the corresponding labels and hides stack views for fields that are not present.
    /// - Parameter payload: A dictionary containing the decoded token data.
    func configure(with payload: [String: Any]) {
        // A helper to set text on a label and manage the visibility of its container stack view.
        func setText(for label: UILabel, stackView: UIStackView, value: Any?) {
            if let value = value {
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

        // Populate each field.
        setText(for: issLabel, stackView: issStackView, value: payload["iss"])
        setText(for: subLabel, stackView: subStackView, value: payload["sub"])
        setText(for: jtiLabel, stackView: jtiStackView, value: payload["jti"])

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

        // Handle timestamp fields by converting them to human-readable dates.
        if let expTimestamp = payload["exp"] as? TimeInterval {
            let date = Date(timeIntervalSince1970: expTimestamp)
            expLabel.text = "\(dateFormatter.string(from: date)) (\(Int(expTimestamp)))"
            expStackView.isHidden = false
        } else {
            expStackView.isHidden = true
        }
        
        if let iatTimestamp = payload["iat"] as? TimeInterval {
            let date = Date(timeIntervalSince1970: iatTimestamp)
            iatLabel.text = "\(dateFormatter.string(from: date)) (\(Int(iatTimestamp)))"
            iatStackView.isHidden = false
        } else {
            iatStackView.isHidden = true
        }
    }
    
    // MARK: - Factory Method

    /// Creates and configures an instance of `DecodedTokenView` from its XIB.
    /// - Parameter payload: The token payload to display.
    /// - Returns: A configured `DecodedTokenView` instance, or `nil` if the payload is empty or the XIB cannot be loaded.
    static func create(with payload: [String: Any]?) -> DecodedTokenView? {
        print("create DecodedTokenView for \(payload ?? [:])")
        guard let payload = payload, !payload.isEmpty else { return nil }
        
        guard let view = Bundle.main.loadNibNamed("DecodedTokenView", owner: nil, options: nil)?.first as? DecodedTokenView else {
            if #available(iOS 14.0, *) {
                Logger.ui.error("Failed to load DecodedTokenView from XIB.")
            }
            return nil
        }
        
        view.configure(with: payload)
        return view
    }
}

@available(iOS 14.0, *)
extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
