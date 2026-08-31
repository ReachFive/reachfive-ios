import Reach5
import UIKit
import WebKit

class SettingsViewController: UIViewController {
    @IBOutlet var environmentDomain: UILabel!
    @IBOutlet var tableView: UITableView!

    private enum Section: Int, CaseIterable {
        case environment
        case versions
        case scopes
        case startupActions
        case cookies
    }

    private let environments = SandboxEnvironment.allCases
    private var selectedEnvironment = SandboxEnvironment.selected
    /// The environment a switch is running towards, if one is: its row shows a spinner, and the section stops
    /// answering taps until the client configuration comes back.
    private var switchingTo: SandboxEnvironment?
    private let versions = SandboxVersions.all

    private var availableScopes: [String] = []
    static var selectedScopes: [String] = [] // TODO: utiliser partout ces scopes là
    private static let selectedScopesKey = "selectedScopes"

    /// Restores the persisted selection, dropping whatever the current client does not offer. The selection
    /// lives under a single key, so a scope ticked on one environment would otherwise be sent to another that
    /// never declared it — and, missing from the Scopes section, would be invisible there.
    static func restoreSelectedScopes(availableScopes: [String]) {
        let persisted = UserDefaults.standard.stringArray(forKey: selectedScopesKey)
        selectedScopes = persisted?.filter { availableScopes.contains($0) } ?? availableScopes
    }

    private let startupActions = [
        "Use refreshAccessToken at startup",
        "Use login with request at startup",
    ]
    private var selectedStartupAction: String?

    private var cookies: [HTTPCookie] = [] {
        didSet {
            Task { @MainActor in
                if let header = self.tableView.headerView(forSection: Section.cookies.rawValue) as? EditableSectionHeaderView {
                    header.setEditButtonHidden(self.cookies.isEmpty)
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        setupTableView()
        loadSettings()
        let cookiesHeaderNib = UINib(nibName: "EditableSectionHeaderView", bundle: nil)
        tableView.register(cookiesHeaderNib, forHeaderFooterViewReuseIdentifier: EditableSectionHeaderView.reuseIdentifier)
        tableView.register(SubtitleCell.self, forCellReuseIdentifier: "settingsEnvironmentCell")
        tableView.register(SubtitleCell.self, forCellReuseIdentifier: "settingsVersionCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "settingsScopeCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "settingsStartupCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "settingsCookieCell")

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
        // The scope selection is not read here: `AppDelegate` restores it against what the current client
        // offers, at launch and after every switch. Reading the key again would undo that filtering.
        // TODO: ces actions seront faite dans applicationDidBecomeActive ou applicationWillEnterForeground, pas dans didFinishLaunchingWithOptions
        // TODO: sur iOS, ajouter ces actions en tant que "Home screen quick action", sur Mac Catalyst, remplacer cette section par un popup button
        // TODO: sur Mac Catalyst, remplacer cette section par un popup button
        selectedStartupAction = defaults.string(forKey: "selectedStartupAction")
        selectedEnvironment = SandboxEnvironment.selected
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(SettingsViewController.selectedScopes, forKey: Self.selectedScopesKey)
        defaults.set(selectedStartupAction, forKey: "selectedStartupAction")
    }

    private func loadCookies() {
        // A domain-scoped cookie comes back dot-prefixed (".reach5.net") and case-folded, so neither an
        // equality check nor a case-sensitive one finds it: compare host-suffix-wise, case-insensitively.
        let domain = AppDelegate.reachfive().sdkConfig.domain.lowercased()
        let sessionCookies = HTTPCookieStorage.shared.cookies?.filter { cookie in
            let cookieDomain = cookie.domain.lowercased()
            return cookieDomain == domain || domain.hasSuffix(cookieDomain.hasPrefix(".") ? cookieDomain : ".\(cookieDomain)")
        } ?? []

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

    @objc func switchChanged(_ sender: UISwitch) {
        let scope = availableScopes[sender.tag]
        if sender.isOn {
            if !SettingsViewController.selectedScopes.contains(scope) {
                SettingsViewController.selectedScopes.append(scope)
            }
        } else {
            SettingsViewController.selectedScopes.removeAll { $0 == scope }
        }
        saveSettings()
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .environment:
            return environments.count
        case .versions:
            return versions.count
        case .scopes:
            return availableScopes.count
        case .startupActions:
            return startupActions.count
        case .cookies:
            return cookies.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .environment:
            return "Environment"
        case .versions:
            return "Versions"
        case .scopes:
            return "Scopes"
        case .startupActions:
            return "Startup Actions"
        case .cookies:
            return "" // Title set in viewForHeaderInSection
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = switch indexPath.section {
        case Section.environment.rawValue: "settingsEnvironmentCell"
        case Section.versions.rawValue: "settingsVersionCell"
        case Section.scopes.rawValue: "settingsScopeCell"
        case Section.startupActions.rawValue: "settingsStartupCell"
        case Section.cookies.rawValue: "settingsCookieCell"
        default: "cell"
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        guard let section = Section(rawValue: indexPath.section) else { return cell }

        switch section {
        case .environment:
            let environment = environments[indexPath.row]
            cell.textLabel?.text = environment.label
            cell.detailTextLabel?.text = environment.domain
            if switchingTo == environment {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessoryView = spinner
                cell.accessoryType = .none
            } else {
                // Cleared explicitly: a recycled cell would keep the spinner of the row it was used for.
                cell.accessoryView = nil
                cell.accessoryType = selectedEnvironment == environment ? .checkmark : .none
            }
        case .versions:
            let component = versions[indexPath.row]
            cell.selectionStyle = .none
            cell.textLabel?.text = component.name
            cell.detailTextLabel?.text = component.detail
        case .scopes:
            cell.selectionStyle = .none
            let scope = availableScopes[indexPath.row]
            cell.textLabel?.text = scope

            let switchView = UISwitch(frame: .zero)
            switchView.setOn(SettingsViewController.selectedScopes.contains(scope), animated: false)
            switchView.tag = indexPath.row
            switchView.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)

            cell.accessoryView = switchView
        case .startupActions:
            let action = startupActions[indexPath.row]
            cell.textLabel?.text = action
            cell.accessoryType = selectedStartupAction == action ? .checkmark : .none
        case .cookies:
            let cookie = cookies[indexPath.row]
            cell.textLabel?.text = cookie.name
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .environment:
            let environment = environments[indexPath.row]
            guard environment != selectedEnvironment else { return }
            switchingTo = environment
            tableView.reloadSections(IndexSet(integer: Section.environment.rawValue), with: .none)
            Task { @MainActor in
                var failure: Error?
                do {
                    try await (UIApplication.shared.delegate as! AppDelegate).switchEnvironment(to: environment)
                } catch {
                    failure = error
                }

                self.switchingTo = nil
                // Read back rather than trust the tap: a switch that was refused, or that failed, must not
                // leave the checkmark somewhere the SDK is not.
                self.selectedEnvironment = SandboxEnvironment.selected
                self.environmentDomain.text = AppDelegate.reachfive().sdkConfig.domain
                self.loadCookies()
                self.loadScopes()
                tableView.reloadSections(IndexSet(integer: Section.environment.rawValue), with: .none)

                if let failure {
                    self.presentErrorAlert(title: "Switching to \(environment.label) failed", failure)
                }
            }
        case .versions, .scopes:
            break
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

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        // A switch is running: its section must not answer, or a second one would rebuild the instance under it.
        if Section(rawValue: indexPath.section) == .environment, switchingTo != nil {
            return nil
        }
        return indexPath
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

    /// The commit editing style function enables the swipe-to-delete functionality and responds to the delete action.
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

/// A plain cell registered by class comes back in the `.default` style, which has no detail label — and the
/// environment rows are unreadable without the domain, the version rows without what they report.
private final class SubtitleCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
