import UIKit
import Reach5

class SessionDeviceCell: UITableViewCell {
    static let reuseIdentifier = "SessionDeviceCell"

    @IBOutlet weak var deviceNameLabel: UILabel!
    @IBOutlet weak var createdAtLabel: UILabel!
    @IBOutlet weak var ipLabel: UILabel!
    @IBOutlet weak var osLabel: UILabel!
    @IBOutlet weak var userAgentLabel: UILabel!
    @IBOutlet weak var deviceClassLabel: UILabel!
    @IBOutlet weak var idLabel: UILabel!
    @IBOutlet weak var locationLabel: UILabel!
    @IBOutlet weak var tokenTypeLabel: UILabel!
    @IBOutlet weak var lastConnectionLabel: UILabel!
    @IBOutlet weak var deleteButton: UIButton!

    var onDelete: (() -> Void)?

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
