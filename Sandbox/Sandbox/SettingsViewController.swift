import UIKit
import Reach5
import WebKit

class SettingsViewController: UIViewController {

    @IBOutlet weak var environmentDomain: UILabel!
    @IBOutlet weak var tableView: UITableView!

    private enum Section: Int, CaseIterable {
        case scopes
        case startupActions
        case cookies
    }

    private var availableScopes: [String] = []
    public static var selectedScopes: [String] = []  //TODO: utiliser partout ces scopes là

    private let startupActions = [
        "Use refreshAccessToken at startup",
        "Use login with request at startup"
    ]
    private var selectedStartupAction: String?

    private var cookies: [HTTPCookie] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        setupTableView()
        loadSettings()
        let cookiesHeaderNib = UINib(nibName: "EditableSectionHeaderView", bundle: nil)
        tableView.register(cookiesHeaderNib, forHeaderFooterViewReuseIdentifier: EditableSectionHeaderView.reuseIdentifier)

        let config = AppDelegate.reachfive().sdkConfig
        environmentDomain.text = config.domain
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadCookies()
        loadScopes()
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        SettingsViewController.selectedScopes = defaults.stringArray(forKey: "selectedScopes") ?? availableScopes
        //TODO: ces actions seront faite dans applicationDidBecomeActive ou applicationWillEnterForeground, pas dans didFinishLaunchingWithOptions
        //TODO: sur iOS, ajouter ces actions en tant que "Home screen quick action", sur Mac Catalyst, remplacer cette section par un popup button
        //TODO: sur Mac Catalyst, remplacer cette section par un popup button
        selectedStartupAction = defaults.string(forKey: "selectedStartupAction")
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(SettingsViewController.selectedScopes, forKey: "selectedScopes")
        defaults.set(selectedStartupAction, forKey: "selectedStartupAction")
    }

    private func loadCookies() {
        let sessionCookies = HTTPCookieStorage.shared.cookies?.filter({ $0.domain == AppDelegate.reachfive().sdkConfig.domain }) ?? []

        DispatchQueue.main.async {
            self.cookies = sessionCookies
            self.tableView.reloadSections(IndexSet(integer: Section.cookies.rawValue), with: .automatic)
        }
    }

    private func loadScopes() {
        DispatchQueue.main.async {
            self.availableScopes = AppDelegate.reachfive().scope
            self.tableView.reloadSections(IndexSet(integer: Section.scopes.rawValue), with: .automatic)
        }
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .scopes:
            return availableScopes.count
        case .startupActions:
            return startupActions.count
        case .cookies:
            return cookies.count > 0 ? cookies.count : 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .scopes:
            return "Scopes"
        case .startupActions:
            return "Startup Actions"
        case .cookies:
            return "" //Title set in viewForHeaderInSection
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.selectionStyle = .none
        guard let section = Section(rawValue: indexPath.section) else { return cell }

        switch section {
        case .scopes:
            let scope = availableScopes[indexPath.row]
            cell.textLabel?.text = scope
            cell.accessoryType = SettingsViewController.selectedScopes.contains(scope) ? .checkmark : .none
        case .startupActions:
            let action = startupActions[indexPath.row]
            cell.textLabel?.text = action
            cell.accessoryType = selectedStartupAction == action ? .checkmark : .none
        case .cookies:
            //TODO: pourquoi le cookie accessoryType.checkmark change de statut à chaque fois qu'on voit la page ?
            if cookies.isEmpty {
                cell.textLabel?.text = "No cookies found."
            } else {
                let cookie = cookies[indexPath.row]
                cell.textLabel?.text = cookie.name
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .scopes:
            let scope = availableScopes[indexPath.row]
            if let index = SettingsViewController.selectedScopes.firstIndex(of: scope) {
                SettingsViewController.selectedScopes.remove(at: index)
            } else {
                SettingsViewController.selectedScopes.append(scope)
            }
            saveSettings()
            tableView.reloadRows(at: [indexPath], with: .automatic)
        case .startupActions:
            let action = startupActions[indexPath.row]
            if selectedStartupAction == action {
                selectedStartupAction = nil
            } else {
                selectedStartupAction = action
            }
            saveSettings()
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let section = Section(rawValue: section) else { return nil }

        if section == .cookies {
            guard let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: EditableSectionHeaderView.reuseIdentifier) as? EditableSectionHeaderView else {
                return nil
            }

            headerView.configure(
                title: "Cookies",
                onEdit: { button in
                    let isEditing = !tableView.isEditing
                    tableView.setEditing(isEditing, animated: true)
                    button.setTitle(isEditing ? "Done" : "Modify", for: .normal)
                }
            )
            headerView.setEditButtonHidden(cookies.isEmpty)

            return headerView
        }

        return nil
    }

    // The commit editing style function enables the swipe-to-delete functionality and responds to the delete action.
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete,
                let section = Section(rawValue: indexPath.section),
                section == .cookies else { return }

        Task { @MainActor in
            HTTPCookieStorage.shared.deleteCookie(cookies[indexPath.row])
            self.cookies.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .cookies
    }
}
