import UIKit
import Reach5

class SessionDevicesController: UIViewController {
    var sessionDevices: [SessionDevice] = [] {
        didSet {
            DispatchQueue.main.async {
                if let header = self.sessionDevicesTableView.headerView(forSection: 0) as? EditableSectionHeaderView {
                    header.setEditButtonHidden(self.sessionDevices.isEmpty)
                }
            }
        }
    }
    
    @IBOutlet weak var sessionDevicesTableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Session Devices"
        
        sessionDevicesTableView.dataSource = self
        sessionDevicesTableView.delegate = self
        
        let nib = UINib(nibName: "SessionDeviceCell", bundle: nil)
        sessionDevicesTableView.register(nib, forCellReuseIdentifier: SessionDeviceCell.reuseIdentifier)
        let sessionDevicesNib = UINib(nibName: "EditableSectionHeaderView", bundle: nil)
        sessionDevicesTableView.register(sessionDevicesNib, forHeaderFooterViewReuseIdentifier: EditableSectionHeaderView.reuseIdentifier)
    }
}

extension SessionDevicesViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return trustedDevices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SessionDeviceCell.reuseIdentifier, for: indexPath) as! SessionDeviceCell
        let device = sessionDevices[indexPath.row]
        cell.configure(with: device)
        return cell
    }
}

extension SessionDevicesViewController: UITableViewDelegate {
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
                let isEditing = !self.sessionDevicesTableView.isEditing
                self.sessionDevicesTableView.setEditing(isEditing, animated: true)
                button.setTitle(isEditing ? "Done" : "Modify", for: .normal)
            }
        )
        headerView.setEditButtonHidden(SessionDevice.isEmpty)
        
        return headerView
    }
}

