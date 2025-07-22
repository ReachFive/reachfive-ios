import UIKit
import Reach5

class TrustedDeviceCell: UITableViewCell {
    static let reuseIdentifier = "TrustedDeviceCell"

    @IBOutlet weak var deviceNameLabel: UILabel!
    @IBOutlet weak var createdAtLabel: UILabel!
    @IBOutlet weak var ipLabel: UILabel!
    @IBOutlet weak var osLabel: UILabel!
    @IBOutlet weak var userAgentLabel: UILabel!
    @IBOutlet weak var deviceClassLabel: UILabel!
    @IBOutlet weak var idLabel: UILabel!
    @IBOutlet weak var userIdLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    func configure(with device: TrustedDevice) {
        deviceNameLabel.text = device.metadata.deviceName ?? "Anonymous device"
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = dateFormatter.date(from: device.createdAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            createdAtLabel.text = displayFormatter.string(from: date)
        } else {
            createdAtLabel.text = device.createdAt
        }

        ipLabel.text = "IP: \(device.metadata.ip ?? "N/A")"
        osLabel.text = "OS: \(device.metadata.operatingSystem ?? "N/A")"
        userAgentLabel.text = "User Agent: \(device.metadata.userAgent ?? "N/A")"
        deviceClassLabel.text = "Device Class: \(device.metadata.deviceClass ?? "N/A")"
        idLabel.text = "ID: \(device.id)"
        userIdLabel.text = "User ID: \(device.userId)"
    }
}
