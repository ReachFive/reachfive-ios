
import UIKit

class ProfileContactInfoCell: UITableViewCell {
    @IBOutlet var fieldNameLabel: UILabel!
    @IBOutlet var valueLabel: UILabel!
    @IBOutlet var verificationStatusImageView: UIImageView!
    @IBOutlet var mfaStatusImageView: UIImageView!
    @IBOutlet var actionButton: UIButton!

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    func configure(fieldName: String, value: String?, isVerified: Bool, isMfaEnrolled: Bool, actions: [UIAction]) {
        fieldNameLabel.text = fieldName
        valueLabel.text = value ?? "Not set"
        verificationStatusImageView.image = isVerified ? UIImage(systemName: "checkmark.shield.fill") : UIImage(systemName: "xmark.shield.fill")
        verificationStatusImageView.tintColor = isVerified ? .green : .red
        mfaStatusImageView.isHidden = !isMfaEnrolled

        if isMfaEnrolled {
            mfaStatusImageView.image = UIImage(systemName: "key.fill")
            mfaStatusImageView.tintColor = .systemBlue
        }

        let menu = UIMenu(title: "Actions", children: actions)
        actionButton.menu = menu
        actionButton.showsMenuAsPrimaryAction = true
    }
}
