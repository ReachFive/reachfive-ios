import Reach5
import UIKit
import WebKit

class SettingsViewController: UIViewController {
    @IBOutlet var environmentDomain: UILabel!
    @IBOutlet var tableView: UITableView!

    private enum Section: Int, CaseIterable {
        case captcha
        case scopes
        case startupActions
        case cookies
    }

    private enum CaptchaRow: Int, CaseIterable {
        case status
        case consumesOnUse
        case obtainCaptchaFoxToken
        case obtainReCaptchaToken
        case clearStore
    }

    private var availableScopes: [String] = []
    static var selectedScopes: [String] = [] // TODO: utiliser partout ces scopes là

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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "settingsScopeCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "settingsStartupCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "settingsCookieCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "settingsCaptchaCell")

        let config = AppDelegate.reachfive().sdkConfig
        environmentDomain.text = config.domain
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadCookies()
        loadScopes()
        tableView.reloadSections(IndexSet(integer: Section.captcha.rawValue), with: .none)
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        SettingsViewController.selectedScopes = defaults.stringArray(forKey: "selectedScopes") ?? availableScopes
        // TODO: ces actions seront faite dans applicationDidBecomeActive ou applicationWillEnterForeground, pas dans didFinishLaunchingWithOptions
        // TODO: sur iOS, ajouter ces actions en tant que "Home screen quick action", sur Mac Catalyst, remplacer cette section par un popup button
        // TODO: sur Mac Catalyst, remplacer cette section par un popup button
        selectedStartupAction = defaults.string(forKey: "selectedStartupAction")
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(SettingsViewController.selectedScopes, forKey: "selectedScopes")
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

    private func configureCaptchaCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.textColor = .label

        guard let row = CaptchaRow(rawValue: indexPath.row) else { return }
        switch row {
        case .status:
            cell.selectionStyle = .none
            if let entry = CaptchaStore.peek() {
                let age = Date().timeIntervalSince(entry.obtainedAt)
                cell.textLabel?.text = "\(entry.provider) · \(entry.action ?? "no action") · \(Int(age))s ago"
                cell.textLabel?.textColor = age > 120 ? .systemRed : .label
            } else {
                cell.textLabel?.text = "No token"
            }
        case .consumesOnUse:
            cell.selectionStyle = .none
            cell.textLabel?.text = "Consume token on use"
            let switchView = UISwitch(frame: .zero)
            switchView.setOn(CaptchaStore.consumesOnUse, animated: false)
            switchView.addTarget(self, action: #selector(consumesOnUseChanged(_:)), for: .valueChanged)
            cell.accessoryView = switchView
        case .obtainCaptchaFoxToken:
            cell.textLabel?.text = "Get a CaptchaFox token"
            cell.accessoryType = .disclosureIndicator
        case .obtainReCaptchaToken:
            cell.textLabel?.text = "Obtenir un jeton reCAPTCHA"
            cell.accessoryType = .disclosureIndicator
        case .clearStore:
            cell.textLabel?.text = "Clear the store"
            cell.textLabel?.textColor = .systemRed
        }
    }

    private func didSelectCaptchaRow(at indexPath: IndexPath) {
        guard let row = CaptchaRow(rawValue: indexPath.row) else { return }
        switch row {
        case .status, .consumesOnUse:
            break
        case .obtainCaptchaFoxToken:
            navigationController?.pushViewController(CaptchaFoxController(), animated: true)
        case .obtainReCaptchaToken:
            navigationController?.pushViewController(ReCaptchaController(), animated: true)
        case .clearStore:
            CaptchaStore.clear()
            tableView.reloadSections(IndexSet(integer: Section.captcha.rawValue), with: .none)
        }
    }

    @objc func consumesOnUseChanged(_ sender: UISwitch) {
        CaptchaStore.consumesOnUse = sender.isOn
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .captcha:
            return CaptchaRow.allCases.count
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
        case .captcha:
            return "Captcha"
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
        case Section.captcha.rawValue: "settingsCaptchaCell"
        case Section.scopes.rawValue: "settingsScopeCell"
        case Section.startupActions.rawValue: "settingsStartupCell"
        case Section.cookies.rawValue: "settingsCookieCell"
        default: "cell"
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        guard let section = Section(rawValue: indexPath.section) else { return cell }

        switch section {
        case .captcha:
            configureCaptchaCell(cell, at: indexPath)
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
        case .captcha:
            didSelectCaptchaRow(at: indexPath)
        case .scopes:
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
