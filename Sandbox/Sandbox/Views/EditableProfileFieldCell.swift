
import UIKit

class EditableProfileFieldCell: UITableViewCell {
    @IBOutlet var fieldNameLabel: UILabel!
    @IBOutlet var valueLabel: UILabel!
    @IBOutlet var valueTextField: UITextField!

    var onTextChanged: ((String?) -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        valueTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }

    func configure(fieldName: String, value: String?, isEditing: Bool) {
        fieldNameLabel.text = fieldName
        valueLabel.text = value
        valueTextField.text = value

        valueLabel.isHidden = isEditing
        valueTextField.isHidden = !isEditing
    }

    @objc private func textFieldDidChange(_ textField: UITextField) {
        onTextChanged?(textField.text)
    }
}
