import UIKit

// A reusable table view header with a title and an actionable "Modify"/"Done" button.
class EditableSectionHeaderView: UITableViewHeaderFooterView {
    // A unique identifier for dequeuing the view.
    static let reuseIdentifier = "EditableSectionHeaderView"

    // A closure that is called when the edit button is tapped.
    // The `sender` button is passed to allow for state changes (e.g., updating the title).
    var onEditButtonTapped: ((UIButton) -> Void)?

    // The button to toggle editing mode for a table view.
    private let editButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Modify", for: .normal)
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Configures the view with a title and the button tap action.
    func configure(title: String, onEdit: @escaping (UIButton) -> Void) {
        titleLabel.text = title
        self.onEditButtonTapped = onEdit
    }

    // Sets up the layout and constraints for the subviews.
    private func setupViews() {
        contentView.addSubview(titleLabel)
        contentView.addSubview(editButton)

        NSLayoutConstraint.activate([
            // Constraints for the title label
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // Constraints for the edit button
            editButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            editButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            // Ensure the title doesn't overlap with the button
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: editButton.leadingAnchor, constant: -8)
        ])
    }

    // The action called when the edit button is tapped.
    @objc private func editButtonAction() {
        onEditButtonTapped?(editButton)
    }
}
