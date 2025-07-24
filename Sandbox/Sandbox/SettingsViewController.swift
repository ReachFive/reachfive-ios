//
//  SettingsViewController.swift
//  Sandbox
//
//  Created by François on 24/07/2025.
//

import UIKit
import Reach5
import WebKit

class SettingsViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .grouped)

    private enum Section: Int, CaseIterable {
        case environment
        case scopes
        case startupActions
        case cookies
    }

    private var availableScopes = ReachFive.Scope.allCases
    private var selectedScopes: [String] = []

    private let startupActions = [
        "Use refreshAccessToken at startup",
        "Use login with request at startup",
        "Use Apple ID credential state at startup"
    ]
    private var selectedStartupActions: [String: Bool] = [:]

    private var cookies: [HTTPCookie] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        setupTableView()
        loadSettings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadCookies()
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        selectedScopes = defaults.stringArray(forKey: "selectedScopes") ?? []
        selectedStartupActions = defaults.dictionary(forKey: "selectedStartupActions") as? [String: Bool] ?? [:]
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(selectedScopes, forKey: "selectedScopes")
        defaults.set(selectedStartupActions, forKey: "selectedStartupActions")
    }

    private func loadCookies() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            DispatchQueue.main.async {
                self?.cookies = cookies
                self?.tableView.reloadSections(IndexSet(integer: Section.cookies.rawValue), with: .automatic)
            }
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
        case .environment:
            return 1
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
        case .environment:
            return "Environment"
        case .scopes:
            return "Scopes"
        case .startupActions:
            return "Startup Actions"
        case .cookies:
            return "Cookies"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.selectionStyle = .none
        guard let section = Section(rawValue: indexPath.section) else { return cell }

        switch section {
        case .environment:
            let config = AppDelegate.reachfive.sdkConfig
            cell.textLabel?.text = "Domain: \(config.domain)"
            cell.textLabel?.numberOfLines = 0
        case .scopes:
            let scope = availableScopes[indexPath.row]
            cell.textLabel?.text = scope.rawValue
            cell.accessoryType = selectedScopes.contains(scope.rawValue) ? .checkmark : .none
        case .startupActions:
            let action = startupActions[indexPath.row]
            cell.textLabel?.text = action
            cell.accessoryType = selectedStartupActions[action] == true ? .checkmark : .none
        case .cookies:
            if cookies.isEmpty {
                cell.textLabel?.text = "No cookies found."
                cell.textLabel?.textColor = .gray
            } else {
                let cookie = cookies[indexPath.row]
                cell.textLabel?.text = "\(cookie.name): \(cookie.value)"
                cell.textLabel?.textColor = .black
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .scopes:
            let scope = availableScopes[indexPath.row].rawValue
            if let index = selectedScopes.firstIndex(of: scope) {
                selectedScopes.remove(at: index)
            } else {
                selectedScopes.append(scope)
            }
            saveSettings()
            tableView.reloadRows(at: [indexPath], with: .automatic)
        case .startupActions:
            let action = startupActions[indexPath.row]
            selectedStartupActions[action] = !(selectedStartupActions[action] ?? false)
            saveSettings()
            tableView.reloadRows(at: [indexPath], with: .automatic)
        default:
            break
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let section = Section(rawValue: section) else { return nil }
        
        if section == .cookies {
            let headerView = UIView()
            
            let titleLabel = UILabel()
            titleLabel.text = "Cookies"
            titleLabel.font = UIFont.boldSystemFont(ofSize: 17)
            
            let refreshButton = UIButton(type: .system)
            refreshButton.setTitle("Refresh", for: .normal)
            refreshButton.addTarget(self, action: #selector(refreshCookies), for: .touchUpInside)
            
            let stackView = UIStackView(arrangedSubviews: [titleLabel, refreshButton])
            stackView.axis = .horizontal
            stackView.distribution = .equalSpacing
            stackView.alignment = .center
            stackView.translatesAutoresizingMaskIntoConstraints = false
            
            headerView.addSubview(stackView)
            
            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
                stackView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
                stackView.topAnchor.constraint(equalTo: headerView.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor)
            ])
            
            return headerView
        }
        
        return nil
    }
    
    @objc private func refreshCookies() {
        loadCookies()
    }
}