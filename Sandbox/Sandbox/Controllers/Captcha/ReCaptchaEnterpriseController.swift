import Reach5
import RecaptchaEnterprise

/// Demo page for reCAPTCHA Enterprise, through Google's native SDK.
///
/// The server verifies these against the Enterprise API rather than the classic one, hence its own
/// `CaptchaProvider`, and its own site key: this wants a key of type **iOS**, created in the Google
/// Cloud console and registered against the app's bundle identifier. The key types are not
/// interchangeable — an Enterprise *Website* key only works through `enterprise.js` in a web page,
/// and this SDK refuses it.
///
/// Production keys also expect the app to carry the App Attest capability; without it Google falls
/// back to a weaker assessment rather than failing outright, which is enough for this page.
class ReCaptchaEnterpriseController: CaptchaController {
    override var siteKeyDefaultsKey: String { "recaptchaEnterpriseSiteKey" }
    override var providerRawValue: String { CaptchaProvider.reCaptchaEnterprise.rawValue }

    /// `fetchClient` is the expensive half of the flow — it is what talks to Google — so it is done
    /// once per site key and reused, as Google's guide asks. Changing the key in the field drops it.
    private var client: RecaptchaClient?
    private var clientSiteKey: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "reCAPTCHA Enterprise"
    }

    override func obtain(siteKey: String, action: String) {
        captchaView.tokenLabel.text = "Fetching…"

        Task { @MainActor in
            do {
                let client = try await fetchClient(for: siteKey)
                let token = try await client.execute(withAction: RecaptchaAction(customAction: action))
                deliver(token: token)
            } catch {
                deliver(error: Self.message(for: error))
            }
        }
    }

    private func fetchClient(for siteKey: String) async throws -> RecaptchaClient {
        if let client, clientSiteKey == siteKey {
            return client
        }

        let client = try await Recaptcha.fetchClient(withSiteKey: siteKey)
        self.client = client
        clientSiteKey = siteKey
        return client
    }

    /// `RecaptchaError` is an `NSError` subclass whose `localizedDescription` says nothing useful; the
    /// message it carries separately is the one worth showing.
    private static func message(for error: Error) -> String {
        guard let recaptchaError = error as? RecaptchaError else {
            return error.localizedDescription
        }
        return recaptchaError.errorMessage
    }
}
