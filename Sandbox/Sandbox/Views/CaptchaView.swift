import UIKit

/// A structural shell shared by the captcha demo pages: a site key field, an action picker, a button
/// to trigger the challenge, the resulting token (truncated) with a copy button, and a container the
/// hosting controller fills with its own `WKWebView`.
class CaptchaView: UIView {
    @IBOutlet var siteKeyField: UITextField!
    @IBOutlet var actionSegmentedControl: UISegmentedControl!
    @IBOutlet var obtainButton: UIButton!
    @IBOutlet var tokenLabel: UILabel!
    @IBOutlet var copyButton: UIButton!
    @IBOutlet var webViewContainer: UIView!

    static func create() -> CaptchaView? {
        Bundle.main.loadNibNamed("CaptchaView", owner: nil, options: nil)?.first as? CaptchaView
    }
}
