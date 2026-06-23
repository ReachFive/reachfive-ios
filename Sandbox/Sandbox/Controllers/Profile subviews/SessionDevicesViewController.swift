import UIKit
import Reach5

class SessionDevicesViewController: UIViewController {
    var sessionDevices: [SessionDevice] = [] {
        didSet {
            DispatchQueue.main.async {
                if let header = self.sessionDevicesTableView.headerView(forSection: 0) as? EditableSectionHeaderView {
                    header.setEditButtonHidden(self.sessionDevices.isEmpty)
                }
                self.sessionDevicesTableView.reloadData()
            }
        }
    }
    var authToken: AuthToken?

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
        return sessionDevices.count
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let authToken = AppDelegate.storage.getToken() else { return }
            Task { @MainActor in
                let element = sessionDevices[indexPath.row]
                do {
                    try await AppDelegate.reachfive().deleteSessionDevice(id: element.id, authToken: authToken)
                    self.sessionDevices.remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .fade)
                } catch {
                    self.presentErrorAlert(title: "Remove Session device failed", error)
                }
            }
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SessionDeviceCell.reuseIdentifier, for: indexPath) as! SessionDeviceCell
        let device = sessionDevices[indexPath.row]
        cell.configure(with: device)
        cell.onDelete = { [weak self] in
            self?.deleteDevice(device, at: indexPath)
        }
        return cell
    }
}

extension SessionDevicesViewController {
    private func deleteDevice(_ device: SessionDevice, at indexPath: IndexPath) {
        guard let authToken = AppDelegate.storage.getToken() else { return }
        Task {
            do {
                try await AppDelegate.reachfive().deleteSessionDevice(id: device.id, authToken: authToken)
                await MainActor.run {
                    self.sessionDevices.remove(at: indexPath.row)
                }
            } catch {
                self.presentErrorAlert(title: "Error deleting device", error)
            }
        }
    }
}

extension SessionDevicesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
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
        headerView.setEditButtonHidden(sessionDevices.isEmpty)
        
        return headerView
    }
}
