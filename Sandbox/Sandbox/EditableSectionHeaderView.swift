import UIKit

// A reusable table view header with a title and an actionable "Modify"/"Done" button.
class EditableSectionHeaderView: UITableViewHeaderFooterView {
    // A unique identifier for dequeuing the view.
    static let reuseIdentifier = "EditableSectionHeaderView"

    // A closure that is called when the edit button is tapped.
    // The `sender` button is passed to allow for state changes (e.g., updating the title).
    var onEditButtonTapped: ((UIButton) -> Void)?
    var onAddButtonTapped: (() -> Void)?

    // The button to toggle editing mode for a table view.
    private let editButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Modify", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let addButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // The label to display the section's title.
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupViews()
        editButton.addTarget(self, action: #selector(editButtonAction), for: .touchUpInside)
        addButton.addTarget(self, action: #selector(addButtonAction), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Configures the view with a title and the button tap action.
    func configure(title: String, onEdit: @escaping (UIButton) -> Void, onAdd: (() -> Void)? = nil) {
        titleLabel.text = title
        self.onEditButtonTapped = onEdit
        self.onAddButtonTapped = onAdd
        addButton.isHidden = onAdd == nil
    }
    
    // Shows or hides the edit button.
    func setEditButtonHidden(_ isHidden: Bool) {
        editButton.isHidden = isHidden
    }

    // Sets up the layout and constraints for the subviews.
    private func setupViews() {
        let stackView = UIStackView(arrangedSubviews: [titleLabel, addButton, editButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    // The action called when the edit button is tapped.
    @objc private func editButtonAction() {
        onEditButtonTapped?(editButton)
    }
    
    @objc private func addButtonAction() {
        onAddButtonTapped?()
    }
}
