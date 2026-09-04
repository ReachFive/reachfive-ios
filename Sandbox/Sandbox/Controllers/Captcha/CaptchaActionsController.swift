import UIKit

/// Edits the action list the captcha pages offer.
///
/// The actions a client accepts are whatever its captcha configuration lists in the console — `login`
/// on one account, `connexion` on another — and the server compares the action sealed in the token
/// against that list. A token minted with an action outside it is refused like any other access
/// denial, so the Sandbox has to be able to name whatever the account under test declares, without a
/// rebuild.
class CaptchaActionsController: UITableViewController, UITextFieldDelegate {
    private enum Section: Int, CaseIterable {
        case actions
        case add
    }

    private var actions: [String] = CaptchaStore.actions

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Captcha actions"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "captchaActionCell")
        tableView.register(TextFieldCell.self, forCellReuseIdentifier: "captchaActionAddCell")
        navigationItem.rightBarButtonItems = [
            editButtonItem,
            UIBarButtonItem(title: "Defaults", style: .plain, target: self, action: #selector(resetTapped)),
        ]
    }

    private func save() {
        CaptchaStore.actions = actions
    }

    @objc private func resetTapped() {
        CaptchaStore.resetActions()
        actions = CaptchaStore.actions
        tableView.reloadSections(IndexSet(integer: Section.actions.rawValue), with: .automatic)
    }

    private func add(_ action: String) {
        let trimmed = action.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !actions.contains(trimmed) else { return }

        actions.append(trimmed)
        save()
        tableView.insertRows(at: [IndexPath(row: actions.count - 1, section: Section.actions.rawValue)], with: .automatic)
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .actions: actions.count
        case .add: 1
        case nil: 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .actions:
            "These names must match the client's captcha configuration exactly, accents included. An empty list restores the default actions. The order is the picker's, and the first one is preselected."
        default:
            nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .actions:
            let cell = tableView.dequeueReusableCell(withIdentifier: "captchaActionCell", for: indexPath)
            cell.textLabel?.text = actions[indexPath.row]
            cell.selectionStyle = .none
            return cell
        case .add:
            let cell = tableView.dequeueReusableCell(withIdentifier: "captchaActionAddCell", for: indexPath)
            (cell as? TextFieldCell)?.field.delegate = self
            return cell
        case nil:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .actions
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }

        actions.remove(at: indexPath.row)
        save()
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .actions
    }

    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let moved = actions.remove(at: source.row)
        actions.insert(moved, at: min(destination.row, actions.count))
        save()
    }

    /// A move out of the actions section would put an action where the text field lives.
    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath, toProposedIndexPath proposed: IndexPath) -> IndexPath {
        Section(rawValue: proposed.section) == .actions ? proposed : IndexPath(row: actions.count - 1, section: Section.actions.rawValue)
    }

    // MARK: - Adding

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        add(textField.text ?? "")
        textField.text = nil
        return false
    }

    /// Adds on leaving the field too, so a name typed and left behind is not silently dropped.
    func textFieldDidEndEditing(_ textField: UITextField) {
        add(textField.text ?? "")
        textField.text = nil
    }
}

/// The one cell that holds a text field, kept as a class so reuse does not stack a new field on the
/// content view at each dequeue.
private class TextFieldCell: UITableViewCell {
    let field = UITextField()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        field.placeholder = "Add an action"
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        field.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            field.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            field.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
