import Reach5
import UIKit
import WebKit

/// Forwards script messages to a weak target, so a `WKUserContentController` holding this proxy does
/// not keep the controller itself alive — `add(_:name:)` retains its handler strongly.
class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Shared shell for a captcha demo page: installs `CaptchaView`, wires its buttons, and writes
/// whatever token comes back through the `captcha` script message to `CaptchaStore`. A subclass only
/// supplies the provider's identity and how it loads its widget into the web view.
class CaptchaWidgetController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static let messageHandlerName = "captcha"

    private(set) var captchaView: CaptchaView!
    private(set) var webView: WKWebView!

    /// The `UserDefaults` key the site key is persisted under. Never a captcha secret — a site key is
    /// public by design — but kept per-provider so trying both does not overwrite either.
    var siteKeyDefaultsKey: String { fatalError("override siteKeyDefaultsKey") }

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

        setupWebView()
        setupActionSegments()

        captchaView.siteKeyField.text = UserDefaults.standard.string(forKey: siteKeyDefaultsKey)
        captchaView.obtainButton.addTarget(self, action: #selector(obtainTapped), for: .touchUpInside)
        captchaView.copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        captchaView.webViewContainer.isHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshActionSegmentsIfNeeded()
    }

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakScriptMessageHandler(target: self), name: Self.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        captchaView.webViewContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: captchaView.webViewContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: captchaView.webViewContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: captchaView.webViewContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: captchaView.webViewContainer.bottomAnchor),
        ])
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

        captchaView.webViewContainer.isHidden = false
        load(siteKey: siteKey, action: selectedAction, into: webView)
    }

    /// Loads the provider's widget into `webView` for `siteKey`, using `action` if the provider takes
    /// one. Called on the main thread, right after `webView` is shown.
    func load(siteKey: String, action: String, into webView: WKWebView) {
        fatalError("override load(siteKey:action:into:)")
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

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName, let token = message.body as? String else { return }

        if token.hasPrefix("error: ") {
            captchaView.tokenLabel.text = token
            captchaView.webViewContainer.isHidden = true
            return
        }

        CaptchaStore.entry = CaptchaStore.Entry(
            token: token,
            provider: providerRawValue,
            action: selectedAction,
            obtainedAt: Date()
        )

        let truncated = token.count > 24 ? "\(token.prefix(24))…" : token
        captchaView.tokenLabel.text = truncated
        captchaView.webViewContainer.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        captchaView.tokenLabel.text = "Page load failed: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        captchaView.tokenLabel.text = "Page load failed: \(error.localizedDescription)"
    }

    // Without a `WKUIDelegate`, a page calling `alert`/`confirm`/`prompt` blocks its JS thread forever —
    // nothing ever calls the completion handler. A captcha vendor's script can do exactly that on an
    // error it otherwise has no visible surface to report (v3 has no widget UI), so these just dismiss
    // immediately rather than actually presenting anything.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }
}
