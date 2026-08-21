import Reach5
import UIKit

class TrustedDeviceCell: UITableViewCell {
    static let reuseIdentifier = "TrustedDeviceCell"

    @IBOutlet var deviceNameLabel: UILabel!
    @IBOutlet var createdAtLabel: UILabel!
    @IBOutlet var ipLabel: UILabel!
    @IBOutlet var osLabel: UILabel!
    @IBOutlet var userAgentLabel: UILabel!
    @IBOutlet var deviceClassLabel: UILabel!
    @IBOutlet var idLabel: UILabel!
    @IBOutlet var userIdLabel: UILabel!

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
