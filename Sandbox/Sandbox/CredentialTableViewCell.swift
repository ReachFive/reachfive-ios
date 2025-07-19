import UIKit
import Reach5

class CredentialTableViewCell: UITableViewCell {
    static let identifier = "CredentialCell"
    
    @IBOutlet weak var idLabel: UILabel!
    @IBOutlet weak var createdAtLabel: UILabel!
    @IBOutlet weak var deleteButton: UIButton!
    
    var onDelete: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
    }

    public func configure(with credential: MfaCredential) {
        idLabel.text = credential.identifier
        createdAtLabel.text = credential.createdAt.components(separatedBy: ".")[0]
    }
    
    @objc private func deleteButtonTapped() {
        onDelete?()
    }
}
