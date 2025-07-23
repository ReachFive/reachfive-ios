import UIKit

// A reusable table view header with a title and an actionable "Modify"/"Done" button.
// This view's layout is defined in EditableSectionHeaderView.xib.
class EditableSectionHeaderView: UITableViewHeaderFooterView {
    // A unique identifier for dequeuing the view.
    static let reuseIdentifier = "EditableSectionHeaderView"

    // Closures that are called when the buttons are tapped.
    var onEditButtonTapped: ((UIButton) -> Void)?
    var onAddButtonTapped: (() -> Void)?

    // IBOutlets connected to the UI elements in the .xib file.
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var addButton: UIButton!
    @IBOutlet weak var editButton: UIButton!

    // Configures the view with a title and the button tap actions.
    func configure(title: String, onEdit: @escaping (UIButton) -> Void, onAdd: (() -> Void)? = nil) {
        titleLabel.text = title
        self.onEditButtonTapped = onEdit
        self.onAddButtonTapped = onAdd
        // The add button is hidden if no action is provided.
        addButton.isHidden = onAdd == nil
    }
    
    // Shows or hides the edit button.
    func setEditButtonHidden(_ isHidden: Bool) {
        editButton.isHidden = isHidden
    }

    // The action called when the add button is tapped.
    @IBAction func addButtonAction() {
        onAddButtonTapped?()
    }
    
    // The action called when the edit button is tapped.
    @IBAction func editButtonAction() {
        onEditButtonTapped?(editButton)
    }
}