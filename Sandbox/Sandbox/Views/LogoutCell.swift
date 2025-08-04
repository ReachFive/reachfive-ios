import UIKit

class LogoutCell: UITableViewCell {
    @IBOutlet weak var revokeSwitch: UISwitch!
    @IBOutlet weak var webLogoutSwitch: UISwitch!
    @IBOutlet weak var logoutButton: UIButton!
    @IBOutlet weak var revokeInfoButton: UIButton!
    @IBOutlet weak var webLogoutInfoButton: UIButton!

    var onLogoutTapped: ((_ revoke: Bool, _ webLogout: Bool) -> Void)?
    var onRevokeInfoTapped: (() -> Void)?
    var onWebLogoutInfoTapped: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        logoutButton.addTarget(self, action: #selector(logoutButtonTapped), for: .touchUpInside)
        revokeInfoButton.addTarget(self, action: #selector(revokeInfoButtonTapped), for: .touchUpInside)
        webLogoutInfoButton.addTarget(self, action: #selector(webLogoutInfoButtonTapped), for: .touchUpInside)
    }

    @objc private func logoutButtonTapped() {
        onLogoutTapped?(revokeSwitch.isOn, webLogoutSwitch.isOn)
    }

    @objc private func revokeInfoButtonTapped() {
        onRevokeInfoTapped?()
    }

    @objc private func webLogoutInfoButtonTapped() {
        onWebLogoutInfoTapped?()
    }
}