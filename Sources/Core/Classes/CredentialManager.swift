import AuthenticationServices
import Foundation

/// Both ASAuthorizationController protocols (delegate and presentationContextProvider) are annotated
/// NS_SWIFT_UI_ACTOR: their callbacks are therefore delivered on the main actor, and the class's @MainActor
/// isolation protects the mutable state shared between the async entry points and those callbacks.
@MainActor
class CredentialManager: NSObject {
    // MARK: - Request context

    /// Requests can overlap: a new request cancels the ones in flight, but the system callback of a
    /// canceled request can still arrive afterwards. All of a request's state therefore lives in a
    /// RequestContext indexed by its controller: each callback finds the context of its own request, and
    /// one request can never overwrite another's state.
    private struct RequestContext {
        /// retained: keeps the system request alive until it completes
        let controller: ASAuthorizationController
        /// anchor for the presentationContextProvider
        let anchor: ASPresentationAnchor
        /// the caller's continuation, resumed exactly once: every resumption goes through removing the
        /// context from the dictionary, and only the removal that succeeds resumes the continuation
        let continuation: CheckedContinuation<ASAuthorization, Error>
    }

    /// Sign In With Apple data, kept between building the request and completing it.
    struct SignInWithApple {
        let nonce: Pkce
        let provider: ConfiguredAppleProvider
    }

    /// requests in flight, indexed by their controller
    private var contexts: [ObjectIdentifier: RequestContext] = [:]

    /// nonisolated: called from ReachFive's synchronous init, outside the main actor
    override nonisolated init() {}

    // MARK: - Request lifecycle

    /// Submits a system request and returns the authorization obtained. Post-processing (server
    /// validation, token exchange) stays in the caller's task, which therefore keeps control of its own
    /// cancellation and errors, and each flow reads in one piece at its entry point.
    ///
    /// The context is registered before submission: since everything runs on the main actor, the
    /// continuation is in place before the delegate can be called.
    ///
    /// Internal for testability: a test drives the method with an inert `submit` (the request is never
    /// submitted to the system) then simulates the delegate callbacks.
    func perform(
        requests: [ASAuthorizationRequest],
        anchor: ASPresentationAnchor,
        using submit: (ASAuthorizationController) -> Void
    ) async throws -> ASAuthorization {
        guard !requests.isEmpty else {
            // ASAuthorizationController requires at least one request. Without this guard, the system
            // would never call the delegate back and the caller would hang forever.
            throw ReachFiveError.TechnicalError(reason: "No authorization request to perform")
        }

        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate = self
        controller.presentationContextProvider = self
        let key = ObjectIdentifier(controller)

        return try await withTaskCancellationHandler {
            // The caller's task may already be canceled by the time we get here: submit nothing.
            try Task.checkCancellation()

            return try await withCheckedThrowingContinuation { continuation in
                // Canceling requests in flight and submitting the new one in the same synchronous block:
                // no other task can run on the main actor in between.
                cancelInFlightRequests()
                contexts[key] = RequestContext(controller: controller, anchor: anchor, continuation: continuation)
                submit(controller)
            }
        } onCancel: {
            // onCancel runs off the main actor; hop back onto it to touch `contexts`. The task hop cannot
            // outrun registering the context: the block above only yields back to the main actor after
            // submission.
            Task { @MainActor in self.cancelBecauseCallerWasCancelled(key) }
        }
    }

    /// Cancels requests in flight, mainly to cancel an auto-fill request before starting a modal one
    /// (otherwise the latter would fail).
    ///
    /// Each canceled request's continuation is resumed here with `.AuthCanceled`, without waiting for the
    /// system's `didCompleteWithError(.canceled)`: that callback is only promised if a flow was actually
    /// running (see the doc of `ASAuthorizationController.cancel()`), and a request the system never calls
    /// back on would leave its caller hanging and its context in memory forever. Any late callback then
    /// finds no context left and is ignored.
    ///
    /// Called by ``perform(requests:anchor:using:)`` in the same synchronous block as submitting the new
    /// request: the app therefore cannot restart an auto-fill request — its usual reaction to
    /// `.AuthCanceled` — before the new request has been submitted.
    ///
    /// Internal for testability.
    func cancelInFlightRequests() {
        let inFlight = Array(contexts.values)
        contexts.removeAll()
        for context in inFlight {
            if #available(iOS 16.0, *) { // cancel() only exists from iOS 16
                context.controller.cancel()
            }
            context.continuation.resume(throwing: ReachFiveError.AuthCanceled)
        }
    }

    /// Resumes the `key` request with `CancellationError` because the caller's task was canceled, and
    /// stops the system request. Deliberately not `.AuthCanceled`: that error signals a user cancellation,
    /// to which apps react by restarting an auto-fill request, whereas here it is the calling screen that
    /// is going away.
    private func cancelBecauseCallerWasCancelled(_ key: ObjectIdentifier) {
        guard let context = contexts.removeValue(forKey: key) else {
            // request already completed, or never registered: nothing to do
            return
        }
        if #available(iOS 16.0, *) {
            context.controller.cancel()
        }
        context.continuation.resume(throwing: CancellationError())
    }

    // MARK: - Signup

    @available(iOS 16.0, *)
    func signUp(withRequest request: SignupOptions, anchor: ASPresentationAnchor, originR5: String? = nil, reachFive: ReachFive) async throws -> AuthToken {
        let options = try await reachFive.reachFiveApi.createWebAuthnSignupOptions(webAuthnSignupOptions: request)
        let registrationRequest = try makeCredentialRegistrationRequest(from: options, friendlyName: request.friendlyName)

        // request.scope is already the space-joined list of scopes (see SignupOptions); we recover it
        // here rather than duplicating the value as a parameter, an OAuth scope token cannot contain a space.
        let scopes = request.scope.components(separatedBy: " ")

        let authorization = try await perform(requests: [registrationRequest], anchor: anchor) {
            $0.performRequests()
        }

        let credential = try registrationCredential(from: authorization)
        let webauthnSignupCredential = WebauthnSignupCredential(webauthnId: options.options.publicKey.user.id, publicKeyCredential: credential)
        let authenticationToken = try await reachFive.reachFiveApi.signupWithWebAuthn(webauthnSignupCredential: webauthnSignupCredential, originR5: originR5)
        return try await reachFive.loginCallback(tkn: authenticationToken.tkn, scopes: scopes, origin: originR5)
    }

    // MARK: - Register

    @available(iOS 16.0, *)
    func registerNewPasskey(withRequest request: NewPasskeyRequest, originWebAuthn: String, authToken: AuthToken, reachFive: ReachFive) async throws {
        let options = try await reachFive.reachFiveApi.createWebAuthnRegistrationOptions(authToken: authToken, registrationRequest: RegistrationRequest(origin: originWebAuthn, friendlyName: request.friendlyName))
        let registrationRequest = try makeCredentialRegistrationRequest(from: options, friendlyName: request.friendlyName)

        let authorization = try await perform(requests: [registrationRequest], anchor: request.anchor) {
            $0.performRequests()
        }

        let credential = try registrationCredential(from: authorization)
        try await reachFive.reachFiveApi.registerWithWebAuthn(authToken: authToken, publicKeyCredential: credential, originR5: request.origin)
    }

    // MARK: - Reset

    @available(iOS 16.0, *)
    func resetPasskeys(withRequest request: ResetPasskeyRequest, originWebAuthn: String, reachFive: ReachFive) async throws {
        let resetOptions = ResetOptions(email: request.email, phoneNumber: request.phoneNumber, verificationCode: request.verificationCode, friendlyName: request.friendlyName, origin: originWebAuthn, clientId: reachFive.sdkConfig.clientId)
        let options = try await reachFive.reachFiveApi.createWebAuthnResetOptions(resetOptions: resetOptions)
        let registrationRequest = try makeCredentialRegistrationRequest(from: options, friendlyName: request.friendlyName)

        let authorization = try await perform(requests: [registrationRequest], anchor: request.anchor) {
            $0.performRequests()
        }

        let credential = try registrationCredential(from: authorization)
        let resetPublicKeyCredential = ResetPublicKeyCredential(resetOptions: resetOptions, publicKeyCredential: credential)
        try await reachFive.reachFiveApi.resetWebAuthn(resetPublicKeyCredential: resetPublicKeyCredential, originR5: request.origin)
    }

    // MARK: - Auto-fill

    @available(macCatalyst, unavailable)
    @available(iOS 16.0, *)
    func beginAutoFillAssistedPasskeySignIn(request: ResolvedNativeLoginRequest, reachFive: ReachFive) async throws -> AuthToken {
        let assertionRequestOptions = try await reachFive.reachFiveApi.createWebAuthnAuthenticationOptions(webAuthnLoginRequest: makeWebAuthnLoginRequest(for: request, reachFive: reachFive))
        let authorizationRequest = try makePasskeyAssertionRequest(assertionRequestOptions, restrictedToAllowedCredentials: false)

        // AutoFill-assisted requests only support ASAuthorizationPlatformPublicKeyCredentialAssertionRequest.
        let authorization = try await perform(requests: [authorizationRequest], anchor: request.anchor) {
            $0.performAutoFillAssistedRequests()
        }

        return try await authenticate(with: authorization, scopes: request.scopes, reachFive: reachFive, originR5: request.origin)
    }

    // MARK: - Non-discoverable

    /// The only possible request here is an assertion restricted to the credentials the server associates
    /// with the username: there is no batch to assemble, the flow builds its own request.
    ///
    /// Deliberately without an `@available` annotation, unlike the other passkey flows: `.Passkey` is the
    /// only case of `NonDiscoverableAuthorization` today, but a security key assertion exists from iOS 15
    /// already and would be a second case here — this method and
    /// ``authenticate(with:scopes:reachFive:originR5:)`` are written so that adding it will not require
    /// raising this flow's own minimum version.
    func login(withNonDiscoverableUsername username: Username, forRequest request: ResolvedNativeLoginRequest, usingModalAuthorizationFor requestTypes: [NonDiscoverableAuthorization], display mode: Mode, reachFive: ReachFive) async throws -> AuthToken {
        let options = try await reachFive.reachFiveApi.createWebAuthnAuthenticationOptions(
            webAuthnLoginRequest: makeWebAuthnLoginRequest(for: request, username: username, reachFive: reachFive)
        )

        // One request per requested type, all built from the same server options. The account is known
        // here, so every request is restricted to the credentials the server associates with it.
        var requests: [ASAuthorizationRequest] = []
        for type in requestTypes {
            switch type {
            case .Passkey:
                // `.Passkey` cannot be constructed below iOS 16, so this branch only ever runs there —
                // the guard is for the compiler, which cannot know it.
                if #available(iOS 16.0, *) {
                    try requests.append(makePasskeyAssertionRequest(options, restrictedToAllowedCredentials: true))
                }
            }
        }

        let authorization = try await perform(requests: requests, anchor: request.anchor) {
            performRequests(on: $0, mode: mode)
        }
        return try await authenticate(with: authorization, scopes: request.scopes, reachFive: reachFive, originR5: request.origin)
    }

    // MARK: - Modal

    func login(withRequest request: ResolvedNativeLoginRequest, usingModalAuthorizationFor requestTypes: [ModalAuthorization], display mode: Mode, appleProvider: ConfiguredAppleProvider?, reachFive: ReachFive) async throws -> LoginFlow {
        let built = try await buildAuthorizationRequests(
            makeWebAuthnLoginRequest(for: request, reachFive: reachFive),
            reachFive: reachFive,
            authorizing: requestTypes,
            appleProvider: appleProvider
        )

        let authorization = try await perform(requests: built.requests, anchor: request.anchor) {
            performRequests(on: $0, mode: mode)
        }

        return try await completeModalLogin(authorization, scopes: request.scopes, siwa: built.siwa, reachFive: reachFive, originR5: request.origin)
    }

    /// Internal for testability
    struct BuiltRequests {
        let requests: [ASAuthorizationRequest]
        /// set when a Sign In With Apple request is part of the batch
        let siwa: SignInWithApple?
    }

    /// Builds the `ASAuthorizationRequest`s for the requested types, in the requested order — the system
    /// presents the credentials in that order.
    ///
    /// A type this function cannot prepare (no Apple provider configured, passkey options unreachable) is
    /// dropped from the batch rather than blocking sign-in when another type can still succeed; the first
    /// dropped reason only surfaces if nothing survives.
    ///
    /// `fetchAuthenticationOptions` makes the network call by default; a test can substitute it to build
    /// the requests without network.
    func buildAuthorizationRequests(
        _ webAuthnLoginRequest: WebAuthnLoginRequest,
        reachFive: ReachFive,
        authorizing requestTypes: [ModalAuthorization],
        appleProvider: ConfiguredAppleProvider? = nil,
        fetchAuthenticationOptions: (ReachFive, WebAuthnLoginRequest) async throws -> AuthenticationOptions = { try await $0.reachFiveApi.createWebAuthnAuthenticationOptions(webAuthnLoginRequest: $1) }
    ) async throws -> BuiltRequests {
        var requests: [ASAuthorizationRequest] = []
        var siwa: SignInWithApple? = nil
        var firstDropped: Error? = nil

        for type in requestTypes {
            do {
                switch type {
                case .Password:
                    // Allow the user to use a saved password, if they have one.
                    requests.append(ASAuthorizationPasswordProvider().createRequest())

                case .SignInWithApple:
                    // Without an Apple provider the request could not be completed (see
                    // completeModalLogin): better not to offer it than to authenticate the user and fail
                    // afterwards.
                    guard let appleProvider else {
                        throw ReachFiveError.TechnicalError(reason: "Sign In With Apple is not available: no Apple provider configured. Check that initialize() completed and that Apple is enabled for this client.")
                    }

                    // Allow the user to use a Sign In With Apple, if they have one.
                    let appleIDRequest = ASAuthorizationAppleIDProvider().createRequest()
                    var appleScopes: [ASAuthorization.Scope] = []
                    if let scope = appleProvider.providerConfig.scope {
                        if scope.contains(where: { s in s == "email" }) {
                            appleScopes.append(.email)
                        }
                        if scope.contains(where: { s in s == "name" }) {
                            appleScopes.append(.fullName)
                        }
                    }
                    appleIDRequest.requestedScopes = appleScopes
                    let siwaNonce = Pkce.generate()
                    appleIDRequest.nonce = siwaNonce.codeChallenge
                    siwa = SignInWithApple(nonce: siwaNonce, provider: appleProvider)

                    requests.append(appleIDRequest)

                case .Passkey:
                    // `.Passkey` cannot be constructed below iOS 16, so this branch only ever runs there —
                    // the guard is for the compiler, which cannot know it.
                    if #available(iOS 16.0, *) {
                        // Allow the user to use a saved passkey, if they have one.
                        let authOptions = try await fetchAuthenticationOptions(reachFive, webAuthnLoginRequest)
                        try requests.append(makePasskeyAssertionRequest(authOptions, restrictedToAllowedCredentials: false))
                    }
                }
            } catch {
                Logger.shared.log("Authorization request dropped for \(type): \(error)")
                firstDropped = firstDropped ?? error
            }
        }

        if requests.isEmpty, let firstDropped {
            throw firstDropped
        }
        return BuiltRequests(requests: requests, siwa: siwa)
    }

    private func performRequests(on controller: ASAuthorizationController, mode: Mode) {
        switch mode {
        case .Always:
            // If credentials are available, presents a modal sign-in sheet.
            // If there are no locally saved credentials, the system presents a QR code to allow signing in with a
            // passkey from a nearby device.
            controller.performRequests()
        case .IfImmediatelyAvailableCredentials:
            // If credentials are available, presents a modal sign-in sheet.
            // If there are no locally saved credentials, no UI appears and
            // the system passes ASAuthorizationError.Code.canceled to call
            // `AccountManager.authorizationController(controller:didCompleteWithError:)`.
            if #available(iOS 16.0, *) { // no need to have a fallback in case iOS < 16, because .IfImmediatelyAvailableCredentials is already requiring iOS 16
                controller.performRequests(options: .preferImmediatelyAvailableCredentials)
            }
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension CredentialManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let anchor = contexts[ObjectIdentifier(controller)]?.anchor else {
            // Should not happen: the context is registered before the request is submitted and removed
            // only once it completes. A detached window is better than a crash, but it would be invisible
            // on screen: log it.
            Logger.shared.log("presentationAnchor: no in-flight request for this controller, falling back to a detached window")
            return ASPresentationAnchor()
        }
        return anchor
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension CredentialManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        takeContext(for: controller)?.continuation.resume(returning: authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        takeContext(for: controller)?.continuation.resume(throwing: Self.adapt(error))
    }

    /// Removes the context as soon as the callback arrives: guarantees a continuation is resumed exactly
    /// once (a second callback for the same controller finds nothing left), and that a later cancellation
    /// can no longer touch a request that already completed.
    private func takeContext(for controller: ASAuthorizationController) -> RequestContext? {
        contexts.removeValue(forKey: ObjectIdentifier(controller))
    }

    /// Pure function, extracted to be unit-testable
    nonisolated static func adapt(_ error: Error) -> ReachFiveError {
        if let authorizationError = error as? ASAuthorizationError {
            if authorizationError.code == .canceled {
                // Either the system doesn't find any credentials and the request ends silently, or the user cancels the request.
                // This is a good time to show a traditional login form, or ask the user to create an account.
                return .AuthCanceled
            }
            // Another ASAuthorization error.
            return .TechnicalError(reason: "ASAuthorizationError \(authorizationError.code.rawValue): \(error)")
        }
        return .TechnicalError(reason: "\(error.localizedDescription)")
    }
}

// MARK: - Extracting received credentials

extension CredentialManager {
    /// Extracts a passkey registration credential from an authorization (signup / add / reset) and
    /// converts it to our format. Throws a technical error if the authorization does not carry one.
    private func registrationCredential(from authorization: ASAuthorization) throws -> RegistrationPublicKeyCredential {
        guard #available(iOS 16.0, *), let credentialRegistration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: expected a passkey registration")
        }
        guard let attestationObject = credentialRegistration.rawAttestationObject else {
            throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no attestationObject")
        }

        let response = R5AuthenticatorAttestationResponse(attestationObject: attestationObject.toBase64Url(), clientDataJSON: credentialRegistration.rawClientDataJSON.toBase64Url())
        let id = credentialRegistration.credentialID.toBase64Url()
        return RegistrationPublicKeyCredential(id: id, rawId: id, type: "public-key", response: response)
    }

    /// Extracts a WebAuthn assertion from an authorization, validates it against the server and returns
    /// the token. Shared by passkey sign-in (auto-fill / non-discoverable) and by the passkey branch of
    /// the modal sign-in. Throws a technical error if the authorization is not a WebAuthn assertion.
    ///
    /// Typed on ``ASAuthorizationPublicKeyCredentialAssertion`` rather than on the platform credential:
    /// the protocol declares every field we read, and a security key assertion conforms to it too, so
    /// supporting security keys will not touch this method.
    private func authenticate(with authorization: ASAuthorization, scopes: [String], reachFive: ReachFive, originR5: String?) async throws -> AuthToken {
        guard #available(iOS 15.0, *), let assertion = authorization.credential as? any ASAuthorizationPublicKeyCredentialAssertion else {
            throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: expected a WebAuthn assertion")
        }

        let signature = assertion.signature.toBase64Url()
        let clientDataJSON = assertion.rawClientDataJSON.toBase64Url()
        let userID = assertion.userID.toBase64Url()
        let id = assertion.credentialID.toBase64Url()
        let authenticatorData = assertion.rawAuthenticatorData.toBase64Url()
        let response = R5AuthenticatorAssertionResponse(authenticatorData: authenticatorData, clientDataJSON: clientDataJSON, signature: signature, userHandle: userID)

        let authenticationToken = try await reachFive.reachFiveApi.authenticateWithWebAuthn(authenticationPublicKeyCredential: AuthenticationPublicKeyCredential(id: id, rawId: id, type: "public-key", response: response))
        return try await reachFive.loginCallback(tkn: authenticationToken.tkn, scopes: scopes, origin: originR5)
    }

    /// Completes a modal sign-in, the only flow that can receive several kinds of credential (password,
    /// Sign In With Apple, or passkey).
    private func completeModalLogin(_ authorization: ASAuthorization, scopes: [String], siwa: SignInWithApple?, reachFive: ReachFive, originR5: String?) async throws -> LoginFlow {
        let reachFiveApi = reachFive.reachFiveApi
        let sdkConfig = reachFive.sdkConfig
        let scope = scopes.joined(separator: " ")

        if let passwordCredential = authorization.credential as? ASPasswordCredential {
            // a password was selected to sign in
            let (email, phoneNumber) = Username.Unspecified(passwordCredential.user).identifiers

            let resp = try await reachFiveApi.loginWithPassword(loginRequest: LoginRequest(
                email: email,
                phoneNumber: phoneNumber,
                customIdentifier: nil, // No custom identifier for login because no custom identifier can be used for signup
                password: passwordCredential.password,
                grantType: "password",
                clientId: sdkConfig.clientId,
                scope: scope,
                origin: originR5
            ))

            return try await reachFive.loginFlow(afterPasswordGrant: resp, scopes: scopes, origin: originR5)
        } else if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let siwa else {
                // Guaranteed by buildAuthorizationRequests: a Sign In With Apple request only ever makes
                // it into the batch together with its SignInWithApple.
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no nonce, no apple provider")
            }
            guard let identityToken = appleIDCredential.identityToken else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no id token returned")
            }
            guard let idToken = String(data: identityToken, encoding: .utf8) else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: unreadable id token \(identityToken)")
            }

            let pkce = Pkce.generate()
            let code = try await reachFiveApi.authorize(params: [
                "provider": siwa.provider.providerConfig.providerWithVariant,
                "client_id": sdkConfig.clientId,
                "id_token": idToken,
                "response_type": "code",
                "redirect_uri": sdkConfig.redirectUri.absoluteString,
                "scope": scope,
                "code_challenge": pkce.codeChallenge,
                "code_challenge_method": pkce.codeChallengeMethod,
                "nonce": siwa.nonce.codeVerifier,
                "origin": originR5,
                "given_name": appleIDCredential.fullName?.givenName,
                "family_name": appleIDCredential.fullName?.familyName,
            ])
            let token = try await reachFive.authWithCode(code: code, pkce: pkce)
            return .AchievedLogin(authToken: token)
        } else {
            // a passkey was selected to sign in
            let authToken = try await authenticate(with: authorization, scopes: scopes, reachFive: reachFive, originR5: originR5)
            return .AchievedLogin(authToken: authToken)
        }
    }
}

// MARK: - Request construction

extension CredentialManager {
    /// The shared basis of the three WebAuthn login flows.
    private func makeWebAuthnLoginRequest(for request: ResolvedNativeLoginRequest, username: Username? = nil, reachFive: ReachFive) -> WebAuthnLoginRequest {
        WebAuthnLoginRequest(clientId: reachFive.sdkConfig.clientId, origin: request.originWebAuthn, username: username, scope: request.scopes)
    }

    /// Builds a passkey registration request from the options returned by the server. Counterpart of
    /// ``makePasskeyAssertionRequest(_:restrictedToAllowedCredentials:)``.
    ///
    /// `friendlyName` is the one the app asked for, not `options.friendlyName`: nothing guarantees the
    /// server echoes back the value it was given, and it is the app's intent that should name the passkey
    /// in the keychain.
    ///
    /// Internal for testability.
    @available(iOS 16.0, *)
    func makeCredentialRegistrationRequest(from options: RegistrationOptions, friendlyName: String) throws -> ASAuthorizationRequest {
        guard let challenge = options.options.publicKey.challenge.decodeBase64Url() else {
            throw ReachFiveError.TechnicalError(reason: "unreadable challenge: \(options.options.publicKey.challenge)")
        }

        guard let userID = options.options.publicKey.user.id.decodeBase64Url() else {
            throw ReachFiveError.TechnicalError(reason: "unreadable userID from public key: \(options.options.publicKey.user.id)")
        }

        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.options.publicKey.rp.id)
        return publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge, name: friendlyName, userID: userID)
    }

    /// Builds a passkey assertion request from the options returned by the server.
    ///
    /// - Parameter restrictedToAllowedCredentials: restricts the request to the credentials listed by the
    ///   server — what the non-discoverable sign-in does, since it already knows the account. Auto-fill
    ///   and the modal sign-in instead let the user choose among their own passkeys.
    ///
    /// The callers carry the availability guard: `.Passkey` cannot be constructed below iOS 16, so its
    /// presence in a request already implies iOS 16 at runtime.
    ///
    /// Internal for testability.
    @available(iOS 16.0, *)
    func makePasskeyAssertionRequest(_ options: AuthenticationOptions, restrictedToAllowedCredentials: Bool) throws -> ASAuthorizationRequest {
        guard let challenge = options.publicKey.challenge.decodeBase64Url() else {
            throw ReachFiveError.TechnicalError(reason: "unreadable challenge: \(options.publicKey.challenge)")
        }

        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.publicKey.rpId)
        let assertionRequest = publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challenge)

        guard restrictedToAllowedCredentials else { return assertionRequest }

        guard let allowedCredentials = options.publicKey.allowCredentials else {
            throw ReachFiveError.AuthFailure(reason: "no allowCredentials returned")
        }
        assertionRequest.allowedCredentials = allowedCredentials
            .compactMap { $0.id.decodeBase64Url() }
            .map(ASAuthorizationPlatformPublicKeyCredentialDescriptor.init(credentialID:))

        return assertionRequest
    }
}
