import UIKit
import Reach5

/// `TrustedDevicesViewController` displays a list of trusted devices for the user.
/// It receives an array of `TrustedDevice` objects and displays them in a table view.
/// Each cell is a `TrustedDeviceCell` which is configured with the details of a device.
class TrustedDevicesViewController: UIViewController {
    
    var trustedDevices: [TrustedDevice] = [] {
        didSet {
            DispatchQueue.main.async {
                if let header = self.trustedDevicesTableView.headerView(forSection: 0) as? EditableSectionHeaderView {
                    header.setEditButtonHidden(self.trustedDevices.isEmpty)
                }
            }
        }
    }
        
    @IBOutlet weak var trustedDevicesTableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Trusted Devices"
        
        trustedDevicesTableView.dataSource = self
        trustedDevicesTableView.delegate = self
        
        let nib = UINib(nibName: "TrustedDeviceCell", bundle: nil)
        trustedDevicesTableView.register(nib, forCellReuseIdentifier: TrustedDeviceCell.reuseIdentifier)
        let trustedDevicesNib = UINib(nibName: "EditableSectionHeaderView", bundle: nil)
        trustedDevicesTableView.register(trustedDevicesNib, forHeaderFooterViewReuseIdentifier: EditableSectionHeaderView.reuseIdentifier)
    }
    
}
extension TrustedDevicesViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return trustedDevices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrustedDeviceCell.reuseIdentifier, for: indexPath) as! TrustedDeviceCell
        let device = trustedDevices[indexPath.row]
        cell.configure(with: device)
        return cell
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let authToken = AppDelegate.storage.getToken() else { return }
            Task { @MainActor in
                let element = trustedDevices[indexPath.row]
                do {
                    try await AppDelegate.reachfive().mfaDelete(trustedDeviceId: element.id, authToken: authToken)
                    self.trustedDevices.remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .fade)
                } catch {
                    self.presentErrorAlert(title: "Remove trusted device failed", error)
                }
            }
        }
    }
}

extension TrustedDevicesViewController: UITableViewDelegate {
    // method to run when table view cell is tapped
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // Use a custom header view for each section.
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: EditableSectionHeaderView.reuseIdentifier) as? EditableSectionHeaderView else {
            return nil
        }
        
        headerView.configure(
            title: "",
            onEdit: { [weak self] button in
                guard let self else { return }
                let isEditing = !self.trustedDevicesTableView.isEditing
                self.trustedDevicesTableView.setEditing(isEditing, animated: true)
                button.setTitle(isEditing ? "Done" : "Modify", for: .normal)
            }
        )
        headerView.setEditButtonHidden(trustedDevices.isEmpty)
        
        return headerView
    }
}

