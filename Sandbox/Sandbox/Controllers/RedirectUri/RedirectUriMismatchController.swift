import Foundation
import Reach5
import UIKit

/// Runs, one flow at a time, the paths where the SDK obtains an authorization code with one `redirect_uri`
/// and exchanges that code with another one, and shows what the backend answers.
///
/// ReachFive compares the two values byte for byte whenever `/oauth/token` is called with
/// `grant_type=authorization_code`, whatever minted the code. A flow started with a caller-supplied
/// redirect URI therefore cannot be completed by an exchange that falls back to `SdkConfig.redirectUri`.
///
/// Every scenario can be run twice: once configured the problematic way, once with the redirect URI left
/// unset so both calls carry the same value. That second run is the control — it shows the flow itself is
/// sound and that only the mismatch breaks it.
class RedirectUriMismatchController: UITableViewController {

    // MARK: - Scenarios

    private enum Scenario: Int, CaseIterable {
        case passwordlessSms
        case passwordlessEmailCode
        case magicLink
        case stepUpWithAuthToken
        case stepUpLoginFlowDeadParameter

        var title: String {
            switch self {
            case .passwordlessSms: "verifyPasswordlessCode — SMS"
            case .passwordlessEmailCode: "verifyPasswordlessCode — email code"
            case .magicLink: "Magic link — interceptPasswordless"
            case .stepUpWithAuthToken: "MFA step up — .AuthTokenFlow"
            case .stepUpLoginFlowDeadParameter: "MFA step up — .LoginFlow's dead redirectUri"
            }
        }

        var explanation: String {
            switch self {
            case .passwordlessSms:
                """
                startPasswordless sends the redirect URI configured above to /identity/v1/passwordless/start, \
                which stores it alongside the challenge. verifyPasswordlessCode then exchanges the code \
                through authWithCode(code:pkce:), whose redirectUri argument is left out, so it falls back to \
                SdkConfig.redirectUri. The two differ and the backend refuses the exchange.
                """
            case .passwordlessEmailCode:
                """
                The same code path, started by email instead of SMS. The message carries both a one-time code \
                and a magic link; this scenario uses the code. Whether that code is readable depends on the \
                email template configured for the account.
                """
            case .magicLink:
                """
                Two separate problems stack up here. A redirect URI other than SdkConfig.redirectUri never \
                reaches interceptPasswordless: routeUrl compares the path, so another path on the same scheme \
                matches nothing, and an https URI comes back through application(_:continue:), which the SDK \
                only offers to its providers. No code is exchanged at all, so the mismatch cannot even happen \
                — the flow simply goes quiet. Use the second run to have the app route the incoming URL \
                itself, which is what it takes to reach the exchange and see it refused.
                """
            case .stepUpWithAuthToken:
                """
                mfaStart(stepUp: .AuthTokenFlow) sends the redirect URI to /identity/v1/mfa/stepup, which \
                embeds it in the step-up token, and that is the value the authorization code carries. \
                ContinueStepUp.verify then exchanges the code with SdkConfig.redirectUri.
                Needs a stored token and a registered MFA credential.
                """
            case .stepUpLoginFlowDeadParameter:
                """
                In the step-up path the backend builds the authentication request from the step-up token and \
                ignores the redirect_uri sent to /identity/v1/passwordless/start. The redirectUri of \
                .LoginFlow is therefore dead: this run passes a URI that is deliberately not registered in \
                the console, and the flow goes through anyway. Success here is the finding, not a failure.
                Needs an account with a password and MFA enabled.
                """
            }
        }

        /// The runs this scenario offers, in the order they are worth trying.
        var runs: [Run] {
            switch self {
            case .magicLink: [.problematic, .problematicWithHostRouting, .control]
            case .stepUpLoginFlowDeadParameter: [.problematic]
            default: [.problematic, .control]
            }
        }

        /// The run whose verdict summarizes the scenario in its header.
        var primaryRun: Run { .problematic }
    }

    /// What a single run is meant to establish.
    private enum Run: Hashable {
        /// The redirect URI is passed to the start call only, the way an integrator would.
        case problematic
        /// The same flow with no redirect URI at all, so start and exchange agree.
        case control
        /// Magic link only: same as `problematic`, plus the app routing the incoming URL itself.
        case problematicWithHostRouting

        var title: String {
            switch self {
            case .problematic: "Run the problematic way"
            case .control: "Run the control (no redirect URI)"
            case .problematicWithHostRouting: "Run again, with the app routing the callback"
            }
        }

        /// Whether this run passes a redirect URI to the start call.
        var passesRedirectUri: Bool { self != .control }
    }

    private enum Verdict {
        case notRun
        case running
        /// The backend refused the exchange because the code was minted for another redirect URI.
        case mismatchRejected(String)
        /// The flow completed when both calls carried the same URI.
        case controlSucceeded(String)
        /// The callback never reached any SDK interception, so no exchange was even attempted.
        case callbackNotRouted(String)
        /// A prerequisite is missing or the start call was refused: nothing was established either way.
        case inconclusive(String)
        /// Anything else, including a mismatch the backend let through.
        case unexpected(String)

        var symbol: String {
            switch self {
            case .notRun: "○"
            case .running: "…"
            case .mismatchRejected: "❌"
            case .controlSucceeded: "✅"
            case .callbackNotRouted: "⛔️"
            case .inconclusive: "⚠️"
            case .unexpected: "❓"
            }
        }

        var detail: String {
            switch self {
            case .notRun: "Not run yet."
            case .running: "Running…"
            case let .mismatchRejected(text): "Mismatch refused by the backend. \(text)"
            case let .controlSucceeded(text): "Control run went through. \(text)"
            case let .callbackNotRouted(text): "No callback reached the SDK. \(text)"
            case let .inconclusive(text): "Inconclusive. \(text)"
            case let .unexpected(text): "Unexpected. \(text)"
            }
        }
    }

    // MARK: - Configuration

    fileprivate enum Field: Int, CaseIterable {
        case testRedirectUri
        case email
        case phoneNumber
        case password

        var title: String {
            switch self {
            case .testRedirectUri: "Test redirect URI"
            case .email: "Email"
            case .phoneNumber: "Phone number"
            case .password: "Password"
            }
        }

        var keyboardType: UIKeyboardType {
            switch self {
            case .testRedirectUri: .URL
            case .email: .emailAddress
            case .phoneNumber: .phonePad
            case .password: .default
            }
        }

        var textContentType: UITextContentType? {
            switch self {
            case .testRedirectUri: .URL
            case .email: .emailAddress
            case .phoneNumber: .telephoneNumber
            case .password: .password
            }
        }
    }

    private enum ConfigurationRow {
        case field(Field)
        case sdkRedirectUri
        case note
    }

    private enum ScenarioRow {
        case explanation
        case uris
        case run(Run)
        case result(Run)
    }

    /// The URI the dead-parameter scenario passes: bogus on purpose, so that the flow going through proves
    /// the backend never looked at it.
    private static let unregisteredUri = URL(string: "https://not-registered.invalid/callback")!

    private static let stepUpScope = ["openid", "email", "profile", "phone", "full_write", "offline_access", "mfa"]

    private var fieldValues: [Field: String] = [:]
    private var verdicts: [Scenario: [Run: Verdict]] = [:]

    /// Set while a magic-link scenario waits for its callback.
    private var pendingMagicLink: CheckedContinuation<AuthToken, Error>?
    private var loginCallbackObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Redirect URI"
        tableView.register(TextFieldCell.self, forCellReuseIdentifier: TextFieldCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.textCellIdentifier)
        tableView.keyboardDismissMode = .interactive

        let sdkConfig = AppDelegate.reachfive().sdkConfig
        // Already registered as a callback URL for this client: ActionController uses it for
        // webviewLogin(.universalLink), and the domain is in the app's applinks entitlement. That makes it
        // both allowed by the backend and able to come back to the app, which the magic-link scenario needs.
        fieldValues[.testRedirectUri] = "https://\(sdkConfig.domain)/universal_link_internal"

        loginCallbackObserver = NotificationCenter.default.addObserver(
            forName: .DidReceiveLoginCallback,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let result = note.userInfo?["result"] as? Result<AuthToken, ReachFiveError> else { return }
            Task { @MainActor in
                self?.resumePendingMagicLink(with: result)
            }
        }
    }

    deinit {
        if let loginCallbackObserver {
            NotificationCenter.default.removeObserver(loginCallbackObserver)
        }
        AppDelegate.pendingDemoUrlHandler = nil
    }

    // MARK: - Table structure

    private static let textCellIdentifier = "textCell"

    private var configurationRows: [ConfigurationRow] {
        Field.allCases.map { ConfigurationRow.field($0) } + [.sdkRedirectUri, .note]
    }

    private func rows(for scenario: Scenario) -> [ScenarioRow] {
        [.explanation, .uris] + scenario.runs.flatMap { [ScenarioRow.run($0), .result($0)] }
    }

    private func scenario(forSection section: Int) -> Scenario? {
        section == 0 ? nil : Scenario(rawValue: section - 1)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1 + Scenario.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let scenario = scenario(forSection: section) else { return configurationRows.count }
        return rows(for: scenario).count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let scenario = scenario(forSection: section) else { return "Configuration" }
        let verdict = self.verdict(scenario, scenario.primaryRun)
        return "\(verdict.symbol)  \(scenario.rawValue + 1) — \(scenario.title)"
    }

    // MARK: - Cells

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let scenario = scenario(forSection: indexPath.section) else {
            return configurationCell(configurationRows[indexPath.row], at: indexPath)
        }
        return scenarioCell(rows(for: scenario)[indexPath.row], of: scenario, at: indexPath)
    }

    private func configurationCell(_ row: ConfigurationRow, at indexPath: IndexPath) -> UITableViewCell {
        switch row {
        case let .field(field):
            let cell = tableView.dequeueReusableCell(withIdentifier: TextFieldCell.reuseIdentifier, for: indexPath) as! TextFieldCell
            cell.configure(field: field, value: fieldValues[field] ?? "") { [weak self] value in
                self?.fieldValues[field] = value
                if field == .testRedirectUri {
                    self?.reloadUriRows()
                }
            }
            return cell

        case .sdkRedirectUri:
            return textCell(
                at: indexPath,
                text: "SdkConfig.redirectUri",
                secondary: AppDelegate.reachfive().sdkConfig.redirectUri.absoluteString,
                monospacedSecondary: true
            )

        case .note:
            return textCell(
                at: indexPath,
                text: """
                A start call refused with access_denied means the test redirect URI is not registered as a \
                callback URL for this client in the ReachFive console — a setup problem, not the one this \
                page is about. The finding is an invalid_request refusal of the code exchange, reported below \
                as "Mismatch refused by the backend".
                """
            )
        }
    }

    private func scenarioCell(_ row: ScenarioRow, of scenario: Scenario, at indexPath: IndexPath) -> UITableViewCell {
        switch row {
        case .explanation:
            return textCell(at: indexPath, text: scenario.explanation)

        case .uris:
            return textCell(at: indexPath, text: uriSummary(for: scenario), monospaced: true)

        case let .run(run):
            let cell = textCell(at: indexPath, text: run.title)
            var content = cell.contentConfiguration as? UIListContentConfiguration
            content?.textProperties.color = view.tintColor
            cell.contentConfiguration = content
            cell.selectionStyle = .default
            return cell

        case let .result(run):
            let verdict = self.verdict(scenario, run)
            return textCell(at: indexPath, text: "\(verdict.symbol) \(verdict.detail)", monospaced: true)
        }
    }

    private func textCell(
        at indexPath: IndexPath,
        text: String,
        secondary: String? = nil,
        monospaced: Bool = false,
        monospacedSecondary: Bool = false
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.textCellIdentifier, for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = text
        content.secondaryText = secondary
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.textProperties.font = monospaced
            ? .monospacedSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .regular)
            : .preferredFont(forTextStyle: .footnote)
        content.secondaryTextProperties.font = monospacedSecondary
            ? .monospacedSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .regular)
            : .preferredFont(forTextStyle: .footnote)
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }

    /// The two URIs the scenario sends, so the difference is visible before anything is run.
    private func uriSummary(for scenario: Scenario) -> String {
        let exchanged = AppDelegate.reachfive().sdkConfig.redirectUri.absoluteString
        switch scenario {
        case .stepUpLoginFlowDeadParameter:
            return """
            start  → \(Self.unregisteredUri.absoluteString)   (ignored by the backend)
            token  → \(exchanged)
            """
        default:
            let started = fieldValues[.testRedirectUri] ?? ""
            return """
            start  → \(started)
            token  → \(exchanged)   \(started == exchanged ? "=" : "≠")
            """
        }
    }

    private func reloadUriRows() {
        let sections = IndexSet(1...Scenario.allCases.count)
        tableView.reloadSections(sections, with: .none)
    }

    // MARK: - Selection

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let scenario = scenario(forSection: indexPath.section),
              case let .run(run) = rows(for: scenario)[indexPath.row]
        else { return }

        view.endEditing(true)
        perform(scenario, run)
    }

    // MARK: - Verdicts

    private func verdict(_ scenario: Scenario, _ run: Run) -> Verdict {
        verdicts[scenario]?[run] ?? .notRun
    }

    @MainActor
    private func set(_ verdict: Verdict, for scenario: Scenario, _ run: Run) {
        verdicts[scenario, default: [:]][run] = verdict
        tableView.reloadSections(IndexSet(integer: scenario.rawValue + 1), with: .none)
    }

    // MARK: - Running a scenario

    private func perform(_ scenario: Scenario, _ run: Run) {
        set(.running, for: scenario, run)
        Task { @MainActor in
            let verdict: Verdict
            do {
                verdict = try await execute(scenario, run)
            } catch {
                verdict = classify(error, for: run)
            }
            set(verdict, for: scenario, run)
        }
    }

    @MainActor
    private func execute(_ scenario: Scenario, _ run: Run) async throws -> Verdict {
        let reachfive = AppDelegate.reachfive()
        let origin = "RedirectUriMismatchController.\(scenario)"

        switch scenario {
        case .passwordlessSms:
            let phoneNumber = try value(of: .phoneNumber)
            try await starting {
                try await reachfive.startPasswordless(.PhoneNumber(
                    phoneNumber: phoneNumber,
                    redirectUri: try redirectUri(for: run),
                    origin: origin
                ))
            }
            let code = try await askVerificationCode(sentBy: "SMS")
            let token = try await reachfive.verifyPasswordlessCode(verifyAuthCodeRequest: VerifyAuthCodeRequest(
                phoneNumber: phoneNumber,
                verificationCode: code,
                origin: origin
            ))
            return exchangeSucceeded(token, run)

        case .passwordlessEmailCode:
            let email = try value(of: .email)
            try await starting {
                try await reachfive.startPasswordless(.Email(
                    email: email,
                    redirectUri: try redirectUri(for: run),
                    origin: origin
                ))
            }
            let code = try await askVerificationCode(sentBy: "email")
            let token = try await reachfive.verifyPasswordlessCode(verifyAuthCodeRequest: VerifyAuthCodeRequest(
                email: email,
                verificationCode: code,
                origin: origin
            ))
            return exchangeSucceeded(token, run)

        case .magicLink:
            let email = try value(of: .email)
            try await starting {
                try await reachfive.startPasswordless(.Email(
                    email: email,
                    redirectUri: try redirectUri(for: run),
                    origin: origin
                ))
            }
            let token = try await awaitMagicLink(routedByHost: run == .problematicWithHostRouting)
            return exchangeSucceeded(token, run)

        case .stepUpWithAuthToken:
            guard let authToken = AppDelegate.storage.getToken() else {
                throw MissingPrerequisite(what: "a stored token — log in first")
            }
            let continueStepUp = try await starting {
                try await reachfive.mfaStart(stepUp: .AuthTokenFlow(
                    authType: .email,
                    authToken: authToken,
                    redirectUri: try redirectUri(for: run),
                    scope: Self.stepUpScope,
                    origin: origin
                ))
            }
            let code = try await askVerificationCode(sentBy: "email")
            let token = try await continueStepUp.verify(code: code)
            return exchangeSucceeded(token, run)

        case .stepUpLoginFlowDeadParameter:
            let email = try value(of: .email)
            let password = try value(of: .password)
            let flow = try await starting {
                try await reachfive.loginWithPassword(email: email, password: password, origin: origin)
            }
            guard case let .OngoingStepUp(stepUpToken, availableTypes) = flow,
                  let authType = availableTypes.first
            else {
                throw MissingPrerequisite(what: "an account with MFA enabled — this one logged straight in")
            }
            let continueStepUp = try await starting {
                try await reachfive.mfaStart(stepUp: .LoginFlow(
                    authType: authType,
                    stepUpToken: stepUpToken,
                    redirectUri: Self.unregisteredUri,
                    origin: origin
                ))
            }
            let code = try await askVerificationCode(sentBy: authType.rawValue)
            let token = try await continueStepUp.verify(code: code)
            // The whole point: an unregistered URI was accepted without a word, which only happens because
            // the backend never reads it in this path.
            return .mismatchRejected("""
                The flow completed with an unregistered redirect URI, so .LoginFlow's redirectUri had no \
                effect at all. \(describe(token))
                """)
        }
    }

    /// The redirect URI a run hands to the start call: the configured one, or none at all for the control.
    private func redirectUri(for run: Run) throws -> URL? {
        guard run.passesRedirectUri else { return nil }
        let text = try value(of: .testRedirectUri)
        guard let uri = URL(string: text) else { throw InvalidRedirectUri(text: text) }
        return uri
    }

    private func value(of field: Field) throws -> String {
        guard let value = fieldValues[field], !value.isEmpty else {
            throw MissingPrerequisite(what: "a \(field.title.lowercased())")
        }
        return value
    }

    /// Runs the call that starts the flow, tagging any failure so it is reported as inconclusive: nothing
    /// can be concluded about the code exchange when the flow never started.
    private func starting<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw StartFailed(underlying: error)
        }
    }

    private func exchangeSucceeded(_ token: AuthToken, _ run: Run) -> Verdict {
        switch run {
        case .control:
            return .controlSucceeded("Both calls carried \(AppDelegate.reachfive().sdkConfig.redirectUri.absoluteString). \(describe(token))")
        case .problematic, .problematicWithHostRouting:
            return .unexpected("The exchange went through despite the two URIs differing. \(describe(token))")
        }
    }

    private func describe(_ token: AuthToken) -> String {
        "Access token obtained, expiring in \(token.expiresIn.map(String.init) ?? "?") s."
    }

    // MARK: - Reading the outcome

    private func classify(_ error: Error, for run: Run) -> Verdict {
        switch error {
        case let missing as MissingPrerequisite:
            return .inconclusive("Fill in \(missing.what).")

        case let invalid as InvalidRedirectUri:
            return .inconclusive(invalid.localizedDescription)

        case let notRouted as CallbackNotRouted:
            return .callbackNotRouted(notRouted.detail)

        case let started as StartFailed:
            if let apiError = apiError(of: started.underlying), apiError.error == "access_denied" {
                return .inconclusive("""
                    The start call refused the redirect URI: it is not registered as a callback URL for this \
                    client in the ReachFive console. \(describe(apiError))
                    """)
            }
            return .inconclusive("The flow never started: \(describe(started.underlying))")

        case ReachFiveError.AuthCanceled:
            return .inconclusive("Cancelled before the code exchange.")

        case let ReachFiveError.RequestError(apiError) where apiError.error == "invalid_request":
            // 400 invalid_request on /oauth/token: the code was minted for another redirect URI.
            if run == .control {
                return .unexpected("The control run was refused as well. \(describe(apiError))")
            }
            return .mismatchRejected(describe(apiError))

        default:
            return .unexpected(describe(error))
        }
    }

    private func apiError(of error: Error) -> ApiError? {
        switch error {
        case let ReachFiveError.RequestError(apiError): apiError
        case let ReachFiveError.AuthFailure(_, apiError): apiError
        case let ReachFiveError.TechnicalError(_, apiError): apiError
        default: nil
        }
    }

    private func describe(_ apiError: ApiError) -> String {
        [apiError.error, apiError.errorDescription ?? apiError.errorUserMsg]
            .compactMap { $0 }
            .joined(separator: " — ")
    }

    private func describe(_ error: Error) -> String {
        (error as? ReachFiveError)?.description ?? String(describing: error)
    }

    // MARK: - Verification code

    @MainActor
    private func askVerificationCode(sentBy channel: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let alert = UIAlertController(
                title: "Verification code",
                message: "Enter the code you received by \(channel).",
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.placeholder = "Verification code"
                textField.keyboardType = .numberPad
                textField.textContentType = .oneTimeCode
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(throwing: ReachFiveError.AuthCanceled)
            })
            let submit = UIAlertAction(title: "Exchange the code", style: .default) { _ in
                guard let code = alert.textFields?.first?.text, !code.isEmpty else {
                    continuation.resume(throwing: ReachFiveError.AuthCanceled)
                    return
                }
                continuation.resume(returning: code)
            }
            alert.addAction(submit)
            alert.preferredAction = submit
            present(alert, animated: true)
        }
    }

    // MARK: - Magic link

    /// Waits for the magic link to bring the app back. With `routedByHost`, the app hands the SDK any URL
    /// the SDK itself declined, which is the only way an URI other than `SdkConfig.redirectUri` reaches
    /// `interceptPasswordless`.
    @MainActor
    private func awaitMagicLink(routedByHost: Bool) async throws -> AuthToken {
        if routedByHost {
            AppDelegate.pendingDemoUrlHandler = { url in
                Task { @MainActor in AppDelegate.reachfive().interceptUrl(url) }
                return true
            }
        }
        defer { AppDelegate.pendingDemoUrlHandler = nil }

        let waitedSeconds: UInt64 = 180
        let timeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: waitedSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self.resumePendingMagicLink(with: .failure(.TechnicalError(reason: "No callback within \(waitedSeconds) s")))
        }
        defer { timeout.cancel() }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                pendingMagicLink = continuation
                presentAlert(
                    title: "Open the magic link",
                    message: "Tap the link in the email sent to \(fieldValues[.email] ?? ""), then come back."
                )
            }
        } catch let error as ReachFiveError {
            // Nothing came back, or what came back carried no code: on this path that means the callback was
            // never handed to any SDK interception, which is the problem that hides the mismatch.
            if !routedByHost, case let .TechnicalError(reason, _) = error {
                throw CallbackNotRouted(detail: """
                    \(reason). An URI other than SdkConfig.redirectUri matches nothing in routeUrl, and an \
                    https one arrives through application(_:continue:), which the SDK offers to its \
                    providers only.
                    """)
            }
            throw error
        }
    }

    @MainActor
    private func resumePendingMagicLink(with result: Result<AuthToken, ReachFiveError>) {
        guard let continuation = pendingMagicLink else { return }
        pendingMagicLink = nil
        continuation.resume(with: result)
    }

    // MARK: - Errors

    private struct MissingPrerequisite: Error {
        let what: String
    }

    private struct InvalidRedirectUri: LocalizedError {
        let text: String
        var errorDescription: String? { "'\(text)' is not a valid URL." }
    }

    /// Wraps a failure of the call that starts a flow, to keep it apart from a failure of the exchange.
    private struct StartFailed: Error {
        let underlying: Error
    }

    private struct CallbackNotRouted: Error {
        let detail: String
    }
}

// MARK: - Configuration cell

/// A labelled text field, reporting every edit so a run always reads the current value.
private final class TextFieldCell: UITableViewCell {
    static let reuseIdentifier = "textFieldCell"

    private let titleLabel = UILabel()
    private let textField = UITextField()
    private var onChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel

        textField.font = .monospacedSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .regular)
        textField.borderStyle = .roundedRect
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.clearButtonMode = .whileEditing
        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)

        let stack = UIStackView(arrangedSubviews: [titleLabel, textField])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
        selectionStyle = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(field: RedirectUriMismatchController.Field, value: String, onChange: @escaping (String) -> Void) {
        titleLabel.text = field.title
        textField.text = value
        textField.keyboardType = field.keyboardType
        textField.textContentType = field.textContentType
        textField.isSecureTextEntry = field == .password
        self.onChange = onChange
    }

    @objc private func editingChanged() {
        onChange?(textField.text ?? "")
    }
}
