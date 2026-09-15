import UIKit

/// Shared shell for a captcha demo page: installs `CaptchaView`, wires its buttons, and writes
/// whatever token the provider hands back to `CaptchaStore`. A subclass supplies the provider's
/// identity and how it mints a token — in a web view (``CaptchaWidgetController``) or through a
/// native SDK (``ReCaptchaEnterpriseController``).
class CaptchaController: UIViewController {
    private(set) var captchaView: CaptchaView!

    /// The `UserDefaults` key the site key is persisted under. Never a captcha secret — a site key is
    /// public by design — but kept per-provider so trying several does not overwrite any of them.
    var siteKeyDefaultsKey: String { fatalError("override siteKeyDefaultsKey") }

    /// Whether this provider seals an action into its token. CaptchaFox does not, so its page hides
    /// the picker rather than offer a choice that changes nothing.
    var usesActions: Bool { true }

    /// The `captcha_provider` value this page writes to `CaptchaStore`.
    var providerRawValue: String { fatalError("override providerRawValue") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        guard let captchaView = CaptchaView.create() else { return }
        self.captchaView = captchaView
        captchaView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(captchaView)
        NSLayoutConstraint.activate([
            captchaView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            captchaView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            captchaView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            captchaView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            captchaView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        captchaView.actionSegmentedControl.isHidden = !usesActions
        if usesActions {
            setupActionSegments()
        }

        captchaView.siteKeyField.text = UserDefaults.standard.string(forKey: siteKeyDefaultsKey)
        captchaView.obtainButton.addTarget(self, action: #selector(obtainTapped), for: .touchUpInside)
        captchaView.copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        captchaView.webViewContainer.isHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshActionSegmentsIfNeeded()
    }

    private func setupActionSegments() {
        captchaView.actionSegmentedControl.removeAllSegments()
        for (index, action) in CaptchaStore.actions.enumerated() {
            captchaView.actionSegmentedControl.insertSegment(withTitle: action, at: index, animated: false)
        }
        captchaView.actionSegmentedControl.selectedSegmentIndex = 0
    }

    /// Rebuilt only when the list actually changed, so coming back to this page does not silently
    /// reset the action that was picked.
    private func refreshActionSegmentsIfNeeded() {
        guard usesActions else { return }

        let control: UISegmentedControl = captchaView.actionSegmentedControl
        let shown = (0 ..< control.numberOfSegments).compactMap { control.titleForSegment(at: $0) }
        if shown != CaptchaStore.actions {
            setupActionSegments()
        }
    }

    /// Read from the control rather than from the store: the list can be edited between building the
    /// segments and reading the choice.
    var selectedAction: String {
        let control: UISegmentedControl = captchaView.actionSegmentedControl
        let index = control.selectedSegmentIndex
        guard index >= 0, index < control.numberOfSegments, let title = control.titleForSegment(at: index) else {
            return CaptchaStore.actions[0]
        }
        return title
    }

    @objc private func obtainTapped() {
        guard let siteKey = captchaView.siteKeyField.text, !siteKey.isEmpty else {
            presentAlert(title: "Site key missing", message: "Enter a site key first.")
            return
        }
        UserDefaults.standard.set(siteKey, forKey: siteKeyDefaultsKey)

        obtain(siteKey: siteKey, action: selectedAction)
    }

    /// Mints a token for `siteKey`, using `action` if the provider takes one, and reports it through
    /// ``deliver(token:)`` or ``deliver(error:)``. Called on the main thread.
    func obtain(siteKey: String, action: String) {
        fatalError("override obtain(siteKey:action:)")
    }

    /// Records a freshly minted token and shows it truncated.
    func deliver(token: String) {
        CaptchaStore.entry = CaptchaStore.Entry(
            token: token,
            provider: providerRawValue,
            action: usesActions ? selectedAction : nil,
            obtainedAt: Date()
        )

        let truncated = token.count > 24 ? "\(token.prefix(24))…" : token
        captchaView.tokenLabel.text = truncated
        captchaView.webViewContainer.isHidden = true
    }

    /// Shows a failure in place of the token. The store keeps whatever it already held: a page that
    /// fails should not silently discard a token obtained earlier.
    func deliver(error: String) {
        captchaView.tokenLabel.text = "error: \(error)"
        captchaView.webViewContainer.isHidden = true
    }

    @objc private func copyTapped() {
        guard let token = CaptchaStore.peek()?.token else { return }
        UIPasteboard.general.string = token

        let originalText = captchaView.tokenLabel.text
        captchaView.tokenLabel.text = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.captchaView.tokenLabel.text = originalText
        }
    }
}
