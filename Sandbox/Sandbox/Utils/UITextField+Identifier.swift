import UIKit

extension UITextField {
    /// The text, or `nil` when the field is left empty.
    var nonEmptyText: String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// The identifier typed in an "Email or phone number" field, split by the only heuristic the Sandbox has,
    /// the same one `Username.Unspecified` uses: an `@` makes an email, anything else a phone number.
    var identifiers: (email: String?, phoneNumber: String?)? {
        guard let text = nonEmptyText else { return nil }
        return text.contains("@") ? (text, nil) : (nil, text)
    }
}
