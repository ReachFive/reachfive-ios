import UIKit
import os.log

/// A reusable view that displays the key-value pairs of a decoded JWT payload.
class DecodedTokenView: UIView {
    
    // MARK: - IBOutlets

    @IBOutlet private var stackView: UIStackView!
    
    // MARK: - View Lifecycle

    override func awakeFromNib() {
        super.awakeFromNib()
        // Basic styling for the stack view that holds the decoded token fields.
        stackView.spacing = 8
    }
    
    // MARK: - Configuration

    /// Configures the view with a dictionary representing the JWT payload.
    /// - Parameter payload: A dictionary containing the decoded token data.
    func configure(with payload: [String: Any]) {
        // Clear any previously displayed data.
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Sort keys for a consistent display order.
        let sortedKeys = payload.keys.sorted()

        for key in sortedKeys {
            guard let value = payload[key] else { continue }
            
            let label = UILabel()
            label.numberOfLines = 0
            label.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            
            let valueString: String
            // Special handling for timestamp values to make them human-readable.
            if let dateValue = value as? TimeInterval {
                let date = Date(timeIntervalSince1970: dateValue)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .medium
                valueString = "\(formatter.string(from: date)) (\(Int(dateValue)))"
            } else if let stringValue = value as? String {
                valueString = stringValue
            } else if let numberValue = value as? NSNumber {
                valueString = numberValue.stringValue
            } else if let arrayValue = value as? [Any] {
                valueString = arrayValue.map { "\($0)" }.joined(separator: ", ")
            } else {
                valueString = String(describing: value)
            }

            label.text = "\(key): \(valueString)"
            stackView.addArrangedSubview(label)
        }
    }
    
    // MARK: - Factory Method

    /// Creates and configures an instance of `DecodedTokenView`.
    /// - Parameter payload: The token payload to display.
    /// - Returns: A configured `DecodedTokenView` instance, or `nil` if the payload is empty.
    static func create(with payload: [String: Any]?) -> DecodedTokenView? {
        guard let payload = payload, !payload.isEmpty else { return nil }
        
        // Load the view from the XIB.
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
