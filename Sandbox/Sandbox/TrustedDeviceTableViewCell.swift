import UIKit
import Reach5

class TrustedDeviceTableViewCell: UITableViewCell {
    static let identifier = "TrustedDeviceCell"
    
    @IBOutlet weak var deviceNameLabel: UILabel!
    @IBOutlet weak var createdAtLabel: UILabel!
    @IBOutlet weak var deleteButton: UIButton!
    
    var onDelete: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
    }

    public func configure(with trustedDevice: TrustedDevice) {
        deviceNameLabel.text = trustedDevice.metadata.deviceName ?? "Unknown Device"
        createdAtLabel.text = trustedDevice.createdAt.components(separatedBy: "T")[0]
    }
    
    @objc private func deleteButtonTapped() {
        onDelete?()
    }
}
