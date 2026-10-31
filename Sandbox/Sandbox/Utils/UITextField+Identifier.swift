import Reach5
import UIKit

extension UITextField {
    /// The text, or `nil` when the field is left empty.
    var nonEmptyText: String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// The identifier typed in an "Email or phone number" field, left to the SDK's own heuristic:
    /// `Username.Unspecified` makes an email of an identifier with an `@`, a phone number of anything else.
    var username: Username? {
        nonEmptyText.map(Username.Unspecified)
    }
}
