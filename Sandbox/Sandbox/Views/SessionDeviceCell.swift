import Reach5
import UIKit

class SessionDeviceCell: UITableViewCell {
    static let reuseIdentifier = "SessionDeviceCell"

    @IBOutlet var deviceNameLabel: UILabel!
    @IBOutlet var createdAtLabel: UILabel!
    @IBOutlet var ipLabel: UILabel!
    @IBOutlet var osLabel: UILabel!
    @IBOutlet var userAgentLabel: UILabel!
    @IBOutlet var deviceClassLabel: UILabel!
    @IBOutlet var idLabel: UILabel!
    @IBOutlet var locationLabel: UILabel!
    @IBOutlet var tokenTypeLabel: UILabel!
    @IBOutlet var lastConnectionLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    func configure(with device: SessionDevice) {
        deviceNameLabel.text = device.deviceName ?? "Anonymous device"

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func formatDate(_ dateString: String) -> String {
            if let date = dateFormatter.date(from: dateString) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateStyle = .short
                displayFormatter.timeStyle = .short
                return displayFormatter.string(from: date)
            }
            return dateString
        }

        createdAtLabel.text = formatDate(device.createdAt)
        lastConnectionLabel.text = "Last: \(formatDate(device.lastConnection))"

        ipLabel.text = "IP: \(device.ip)"
        osLabel.text = "OS: \(device.operatingSystem ?? "N/A")"
        userAgentLabel.text = "UA: \(device.userAgentName ?? "N/A")"
        deviceClassLabel.text = "Class: \(device.deviceClass ?? "N/A")"
        idLabel.text = "ID: \(device.id)"

        let location = [device.city, device.country].compactMap { $0 }.joined(separator: ", ")
        locationLabel.text = location.isEmpty ? "Location: N/A" : "Location: \(location)"

        tokenTypeLabel.text = "Token: \(device.tokenType.rawValue)"
    }
}
