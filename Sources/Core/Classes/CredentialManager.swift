import Foundation
import AuthenticationServices

public class CredentialManager: NSObject {
    let reachFiveApi: ReachFiveApi
    let storage: Storage

    // MARK: - these fields serve to remember the context between the start of a request and its completion
    // Do not erase them at the end of a request because requests can be interleaved (modal and auto-fill requests)

    // continuation for authentification which can result in an MFA step up (login with password)
    var continuationWithStepUp: CheckedContinuation<LoginFlow, Error>?
    // continuation for normal authentification
    var continuationWithAuthToken: CheckedContinuation<AuthToken, Error>?
    // continuation for new key registration
    var continuationRegistration: CheckedContinuation<Void, Error>?

    // anchor for presentationContextProvider
    var authenticationAnchor: ASPresentationAnchor?

    // the controller for the current request, to cancel it before starting a new request (mainly to cancel an auto-fill request when starting a modal request)
    var authController: ASAuthorizationController?

    // data for signup/register
    var passkeyCreationType: PasskeyCreationType?
    // differentiate between login disco/non-disco
    var requestLoginType: RequestLoginType?
    // the scope of the request
    var scope: String?
    // optional origin for user events
    var originR5: String?
    // the nonce for Sign In With Apple
    var nonce: Pkce?
    var appleProvider: ConfiguredAppleProvider?

    enum PasskeyCreationType {
        case Signup(signupOptions: RegistrationOptions)
        case AddPasskey(authToken: AuthToken)
        case ResetPasskey(resetOptions: ResetOptions)
    }

    enum RequestLoginType {
        case WithPassword
        case WithoutPassword
    }

    // MARK: -

    public init(reachFiveApi: ReachFiveApi, storage: Storage) {
        self.reachFiveApi = reachFiveApi
        self.storage = storage
    }

    // MARK: - Signup
    @available(iOS 16.0, *)
    func signUp(withRequest request: SignupOptions, anchor: ASPresentationAnchor, originR5: String? = nil) async throws -> AuthToken {
        authController?.cancel()
        authenticationAnchor = anchor
        scope = request.scope
        self.originR5 = originR5

        let options = try await reachFiveApi.createWebAuthnSignupOptions(webAuthnSignupOptions: request)
        self.passkeyCreationType = .Signup(signupOptions: options)

        guard let challenge = options.options.publicKey.challenge.decodeBase64Url() else {
            throw ReachFiveError.TechnicalError(reason: "unreadable challenge: \(options.options.publicKey.challenge)")
        }

        guard let userID = options.options.publicKey.user.id.decodeBase64Url() else {
            throw ReachFiveError.TechnicalError(reason: "unreadable userID from public key: \(options.options.publicKey.user.id)")
        }

        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.options.publicKey.rp.id)
        let registrationRequest = publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge, name: request.friendlyName, userID: userID)

        let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performRequests()
        self.authController = authController

        return try await withCheckedThrowingContinuation { continuation in
            self.continuationWithAuthToken = continuation
        }
    }


    // MARK: - Register
    @available(iOS 16.0, *)
    func registerNewPasskey(withRequest request: NewPasskeyRequest, authToken: AuthToken) async throws {
        // Here it is very important to cancel a running auto-fill request, otherwise it will fail like other modal requests
        // so can't separate this method from the rest of the class
        authController?.cancel()
        authenticationAnchor = request.anchor
        self.originR5 = request.origin

        let options = try await reachFiveApi.createWebAuthnRegistrationOptions(authToken: authToken, registrationRequest: RegistrationRequest(origin: request.originWebAuthn!, friendlyName: request.friendlyName))
        self.passkeyCreationType = .AddPasskey(authToken: authToken)

        guard let challenge = options.options.publicKey.challenge.decodeBase64Url() else {
            throw ReachFiveError.TechnicalError(reason: "unreadable challenge: \(options.options.publicKey.challenge)")
        }

        guard let userID = options.options.publicKey.user.id.decodeBase64Url() else {
            throw ReachFiveError.TechnicalError(reason: "unreadable userID from public key: \(options.options.publicKey.user.id)")
        }

        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.options.publicKey.rp.id)
        let registrationRequest = publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge, name: request.friendlyName, userID: userID)

        let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performRequests()
        self.authController = authController

        return try await withCheckedThrowingContinuation { continuation in
            self.continuationRegistration = continuation
        }
    }

    // MARK: - Reset
    @available(iOS 16.0, *)
    func resetPasskeys(withRequest request: ResetPasskeyRequest) async throws {
        // Here it is very important to cancel a running auti-fill request, otherwise it will fail like other modal requests
        // so can't separate this method from the rest of the class
        authController?.cancel()
        authenticationAnchor = request.anchor
        self.originR5 = request.origin

        let resetOptions = ResetOptions(email: request.email, phoneNumber: request.phoneNumber, verificationCode: request.verificationCode, friendlyName: request.friendlyName, origin: request.originWebAuthn!, clientId: reachFiveApi.sdkConfig.clientId)
        let options = try await reachFiveApi.createWebAuthnResetOptions(resetOptions: resetOptions)
        self.passkeyCreationType = .ResetPasskey(resetOptions: resetOptions)

        guard let challenge = options.options.publicKey.challenge.decodeBase64Url() else {
            throw ReachFiveError.TechnicalError(reason: "unreadable challenge: \(options.options.publicKey.challenge)")
        }

        guard let userID = options.options.publicKey.user.id.decodeBase64Url() else {
            throw ReachFiveError.TechnicalError(reason: "unreadable userID from public key: \(options.options.publicKey.user.id)")
        }

        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.options.publicKey.rp.id)
        let registrationRequest = publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge, name: request.friendlyName, userID: userID)

        let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performRequests()
        self.authController = authController

        return try await withCheckedThrowingContinuation { continuation in
            self.continuationRegistration = continuation
        }
    }

    // MARK: - Auto-fill
    @available(macCatalyst, unavailable)
    @available(iOS 16.0, *)
    func beginAutoFillAssistedPasskeySignIn(request: NativeLoginRequest) async throws -> AuthToken {
        authController?.cancel()
        authenticationAnchor = request.anchor
        originR5 = request.origin

        let webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFiveApi.sdkConfig.clientId, origin: request.originWebAuthn!, scope: request.scopes)
        scope = webAuthnLoginRequest.scope

        let assertionRequestOptions = try await reachFiveApi.createWebAuthnAuthenticationOptions(webAuthnLoginRequest: webAuthnLoginRequest)
        let authorizationRequest = try createCredentialAssertionRequest(assertionRequestOptions)

        self.requestLoginType = .WithoutPassword
        // AutoFill-assisted requests only support ASAuthorizationPlatformPublicKeyCredentialAssertionRequest.
        let authController = ASAuthorizationController(authorizationRequests: [authorizationRequest])
        authController.delegate = self
        authController.presentationContextProvider = self
        authController.performAutoFillAssistedRequests()
        self.authController = authController

        return try await withCheckedThrowingContinuation { continuation in
            self.continuationWithAuthToken = continuation
        }
    }

    // MARK: - Modal
    func login(withNonDiscoverableUsername username: Username, forRequest request: NativeLoginRequest, usingModalAuthorizationFor requestTypes: [NonDiscoverableAuthorization], display mode: Mode) async throws -> AuthToken {
        if #available(iOS 16.0, *) { authController?.cancel() }
        authenticationAnchor = request.anchor
        originR5 = request.origin

        let webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFiveApi.sdkConfig.clientId, origin: request.originWebAuthn!, scope: request.scopes)
        switch username {

        case .Unspecified(username: let username):
            if username.contains("@") {
                webAuthnLoginRequest.email = username
            } else {
                webAuthnLoginRequest.phoneNumber = username
            }
        case .Email(email: let email):
            webAuthnLoginRequest.email = email
        case .PhoneNumber(phoneNumber: let phoneNumber):
            webAuthnLoginRequest.phoneNumber = phoneNumber
        }

        let authzs = requestTypes.compactMap { adaptAuthz($0) }

        self.requestLoginType = .WithoutPassword

        try await signInWith(webAuthnLoginRequest, withMode: mode, authorizing: authzs) { assertionRequestOptions in
            guard #available(iOS 16.0, *) else { // can't happen, because this is called from a >= iOS 16 context
                throw ReachFiveError.TechnicalError(reason: "Must be iOS 16 or higher")
            }
            let assertionRequest = try self.createCredentialAssertionRequest(assertionRequestOptions)
            guard let allowedCredentials = assertionRequestOptions.publicKey.allowCredentials else {
                throw ReachFiveError.AuthFailure(reason: "no allowCredentials returned")
            }

            let credentialIDs = allowedCredentials.compactMap { $0.id.decodeBase64Url() }
            assertionRequest.allowedCredentials = credentialIDs.map(ASAuthorizationPlatformPublicKeyCredentialDescriptor.init(credentialID:))

            return assertionRequest
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuationWithAuthToken = continuation
        }
    }

    func login(withRequest request: NativeLoginRequest, usingModalAuthorizationFor requestTypes: [ModalAuthorization], display mode: Mode, appleProvider: ConfiguredAppleProvider?) async throws -> LoginFlow {
        if #available(iOS 16.0, *) { authController?.cancel() }
        authenticationAnchor = request.anchor
        originR5 = request.origin

        let webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFiveApi.sdkConfig.clientId, origin: request.originWebAuthn!, scope: request.scopes)

        self.requestLoginType = .WithPassword

        try await signInWith(webAuthnLoginRequest, withMode: mode, authorizing: requestTypes, appleProvider: appleProvider) { authenticationOptions in
            guard #available(iOS 16.0, *) else { // can't happen, because this is called from a >= iOS 15 context
                throw ReachFiveError.TechnicalError(reason: "Must be iOS 16 or higher")
            }
            return try self.createCredentialAssertionRequest(authenticationOptions)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuationWithStepUp = continuation
        }
    }

    private func signInWith(_ webAuthnLoginRequest: WebAuthnLoginRequest, withMode mode: Mode, authorizing requestTypes: [ModalAuthorization], appleProvider: ConfiguredAppleProvider? = nil, makeAuthorization: @escaping (AuthenticationOptions) throws -> ASAuthorizationRequest) async throws {
        scope = webAuthnLoginRequest.scope

        var requests: [ASAuthorizationRequest] = []

        for type in requestTypes {
            switch type {
            case .Password:
                // Allow the user to use a saved password, if they have one.
                let passwordRequest = ASAuthorizationPasswordProvider().createRequest()
                requests.append(passwordRequest)

            case .SignInWithApple:
                // Allow the user to use a Sign In With Apple, if they have one.
                let appleIDRequest = ASAuthorizationAppleIDProvider().createRequest()
                var appleScopes: [ASAuthorization.Scope] = []
                if let scope = appleProvider?.providerConfig.scope {
                    if scope.contains(where: { s in s == "email"}) {
                        appleScopes.append(.email)
                    }
                    if scope.contains(where: { s in s == "name"}) {
                        appleScopes.append(.fullName)
                    }
                }
                appleIDRequest.requestedScopes = appleScopes
                self.nonce = Pkce.generate()
                appleIDRequest.nonce = self.nonce?.codeChallenge

                self.appleProvider = appleProvider

                requests.append(appleIDRequest)

            case .Passkey:
                do {
                    // Allow the user to use a saved passkey, if they have one.
                    let authOptions = try await self.reachFiveApi.createWebAuthnAuthenticationOptions(webAuthnLoginRequest: webAuthnLoginRequest)
                    let passkeyRequest = try makeAuthorization(authOptions)
                    requests.append(passkeyRequest)
                } catch _ where requestTypes.count > 1 {
                    // if there are other types of requests, do not block auth if only passkey fails. Just eat the error
                }
            }
        }

        let authController = ASAuthorizationController(authorizationRequests: requests)
        authController.delegate = self
        authController.presentationContextProvider = self
        switch mode {
        case .Always:
            // If credentials are available, presents a modal sign-in sheet.
            // If there are no locally saved credentials, the system presents a QR code to allow signing in with a
            // passkey from a nearby device.
            authController.performRequests()
        case .IfImmediatelyAvailableCredentials:
            // If credentials are available, presents a modal sign-in sheet.
            // If there are no locally saved credentials, no UI appears and
            // the system passes ASAuthorizationError.Code.canceled to call
            // `AccountManager.authorizationController(controller:didCompleteWithError:)`.
            if #available(iOS 16.0, *) { // no need to have a fallback in case iOS < 16, because .IfImmediatelyAvailableCredentials is already requiring iOS 16
                authController.performRequests(options: .preferImmediatelyAvailableCredentials)
            }
        }

        self.authController = authController
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension CredentialManager: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        authenticationAnchor!
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension CredentialManager: ASAuthorizationControllerDelegate {

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task {
            defer {
                continuationWithAuthToken = nil
                continuationRegistration = nil
                continuationWithStepUp = nil
            }

            do {
                if let passwordCredential = authorization.credential as? ASPasswordCredential {
                    guard let scope else {
                        throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no scope")
                    }

                    // a password was selected to sign in
                    let email: String?
                    let phoneNumber: String?
                    if passwordCredential.user.contains("@") {
                        email = passwordCredential.user
                        phoneNumber = nil
                    } else {
                        email = nil
                        phoneNumber = passwordCredential.user
                    }

                    let resp = try await reachFiveApi.loginWithPassword(loginRequest: LoginRequest(
                        email: email,
                        phoneNumber: phoneNumber,
                        customIdentifier: nil, // No custom identifier for login because no custom identifier can be used for signup
                        password: passwordCredential.password,
                        grantType: "password",
                        clientId: reachFiveApi.sdkConfig.clientId,
                        scope: scope
                    ))

                    let loginFlow: LoginFlow
                    if resp.mfaRequired == true {
                        let pkce = Pkce.generate()
                        self.storage.save(key: "PASSWORDLESS_PKCE", value: pkce)
                        let stepUpResp = try await self.reachFiveApi.startMfaStepUp(StartMfaStepUpRequest(clientId: self.reachFiveApi.sdkConfig.clientId, redirectUri: self.reachFiveApi.sdkConfig.redirectUri, pkce: pkce, scope: scope, tkn: resp.tkn))
                        loginFlow = .OngoingStepUp(token: stepUpResp.token, availableMfaCredentialItemTypes: stepUpResp.amr)
                    } else {
                        let token = try await self.loginCallback(tkn: resp.tkn, scope: scope, origin: self.originR5)
                        loginFlow = .AchievedLogin(authToken: token)
                    }

                    continuationWithStepUp?.resume(returning: loginFlow)
                } else if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                    guard let nonce, let scope, let appleProvider else {
                        throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no scope, no nonce, no apple provider")
                    }

                    guard let identityToken = appleIDCredential.identityToken else {
                        throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no id token returned")
                    }

                    guard let idToken = String(data: identityToken, encoding: .utf8) else {
                        throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: unreadable id token \(identityToken)")
                    }

                    let pkce = Pkce.generate()
                    let code = try await reachFiveApi.authorize(params: [
                        "provider": appleProvider.providerConfig.providerWithVariant,
                        "client_id": reachFiveApi.sdkConfig.clientId,
                        "id_token": idToken,
                        "response_type": "code",
                        "redirect_uri": reachFiveApi.sdkConfig.scheme,
                        "scope": scope,
                        "code_challenge": pkce.codeChallenge,
                        "code_challenge_method": pkce.codeChallengeMethod,
                        "nonce": nonce.codeVerifier,
                        "origin": originR5,
                        "given_name": appleIDCredential.fullName?.givenName,
                        "family_name": appleIDCredential.fullName?.familyName
                    ])
                    let token = try await self.authWithCode(code: code, pkce: pkce)
                    continuationWithStepUp?.resume(returning: .AchievedLogin(authToken: token))
                } else if #available(iOS 16.0, *), let credentialRegistration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
                    // A new passkey was registered
                    guard let attestationObject = credentialRegistration.rawAttestationObject else {
                        throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no attestationObject")
                    }

                    let clientDataJSON = credentialRegistration.rawClientDataJSON
                    let r5AuthenticatorAttestationResponse = R5AuthenticatorAttestationResponse(attestationObject: attestationObject.toBase64Url(), clientDataJSON: clientDataJSON.toBase64Url())

                    let id = credentialRegistration.credentialID.toBase64Url()
                    let registrationPublicKeyCredential = RegistrationPublicKeyCredential(id: id, rawId: id, type: "public-key", response: r5AuthenticatorAttestationResponse)

                    guard let passkeyCreationType else {
                        throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no signupOptions")
                    }

                    switch passkeyCreationType {
                    case let .AddPasskey(authToken):
                        try await reachFiveApi.registerWithWebAuthn(authToken: authToken, publicKeyCredential: registrationPublicKeyCredential, originR5: self.originR5)
                        continuationRegistration?.resume(returning: ())

                    case let .Signup(signupOptions):
                        guard let scope else {
                            throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no scope")
                        }

                        let webauthnSignupCredential = WebauthnSignupCredential(webauthnId: signupOptions.options.publicKey.user.id, publicKeyCredential: registrationPublicKeyCredential)
                        let authenticationToken = try await reachFiveApi.signupWithWebAuthn(webauthnSignupCredential: webauthnSignupCredential, originR5: self.originR5)
                        let authToken = try await self.loginCallback(tkn: authenticationToken.tkn, scope: scope, origin: self.originR5)
                        continuationWithAuthToken?.resume(returning: authToken)

                    case let .ResetPasskey(resetOptions):
                        let resetPublicKeyCredential = ResetPublicKeyCredential(resetOptions: resetOptions, publicKeyCredential: registrationPublicKeyCredential)
                        try await reachFiveApi.resetWebAuthn(resetPublicKeyCredential: resetPublicKeyCredential, originR5: self.originR5)
                        continuationRegistration?.resume(returning: ())
                    }
                } else if #available(iOS 16.0, *), let credentialAssertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                    // A passkey was selected to sign in

                    guard let requestLoginType else {
                        throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: requestLoginType")
                    }

                    guard let scope else {
                        throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no scope")
                    }

                    let signature = credentialAssertion.signature.toBase64Url()
                    let clientDataJSON = credentialAssertion.rawClientDataJSON.toBase64Url()
                    let userID = credentialAssertion.userID.toBase64Url()

                    let id = credentialAssertion.credentialID.toBase64Url()
                    let authenticatorData = credentialAssertion.rawAuthenticatorData.toBase64Url()
                    let response = R5AuthenticatorAssertionResponse(authenticatorData: authenticatorData, clientDataJSON: clientDataJSON, signature: signature, userHandle: userID)

                    let authenticationToken = try await reachFiveApi.authenticateWithWebAuthn(authenticationPublicKeyCredential: AuthenticationPublicKeyCredential(id: id, rawId: id, type: "public-key", response: response))
                    let authToken = try await self.loginCallback(tkn: authenticationToken.tkn, scope: scope, origin: self.originR5)

                    switch requestLoginType {
                    case .WithPassword: continuationWithStepUp?.resume(returning: .AchievedLogin(authToken: authToken))
                    case .WithoutPassword: continuationWithAuthToken?.resume(returning: authToken)
                    }
                } else {
                    throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: Received unknown authorization type.")
                }
            } catch {
                continuationWithAuthToken?.resume(throwing: error)
                continuationWithStepUp?.resume(throwing: error)
                continuationRegistration?.resume(throwing: error)
            }
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer {
            continuationWithAuthToken = nil
            continuationRegistration = nil
            continuationWithStepUp = nil
        }
        let reachFiveError: ReachFiveError

        if let authorizationError = error as? ASAuthorizationError {
            if authorizationError.code == .canceled {
                // Either the system doesn't find any credentials and the request ends silently, or the user cancels the request.
                // This is a good time to show a traditional login form, or ask the user to create an account.
                reachFiveError = .AuthCanceled
            } else {
                // Another ASAuthorization error.
                reachFiveError = .TechnicalError(reason: "\(error)")
            }
        } else {
            reachFiveError = .TechnicalError(reason: "\(error.localizedDescription)")
        }

        continuationWithStepUp?.resume(throwing: reachFiveError)
        continuationRegistration?.resume(throwing: reachFiveError)
        continuationWithAuthToken?.resume(throwing: reachFiveError)
    }
}

// MARK: - utilities
extension CredentialManager {
    @available(iOS 16.0, *)
    private func createCredentialAssertionRequest(_ assertionRequestOptions: AuthenticationOptions) throws -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest {
        guard let challenge = assertionRequestOptions.publicKey.challenge.decodeBase64Url() else {
            throw ReachFiveError.TechnicalError(reason: "unreadable challenge: \(assertionRequestOptions.publicKey.challenge)")
        }

        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: assertionRequestOptions.publicKey.rpId)
        return publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challenge)
    }

    private func adaptAuthz(_ nda: NonDiscoverableAuthorization) -> ModalAuthorization? {
        if #available(iOS 16.0, *), nda == .Passkey {
            return ModalAuthorization.Passkey
        }
        return nil
    }

    func loginCallback(tkn: String, scope: String, origin: String? = nil) async throws -> AuthToken {
        let pkce = Pkce.generate()

        let code = try await reachFiveApi.loginCallback(loginCallback: LoginCallback(sdkConfig: reachFiveApi.sdkConfig, scope: scope, pkce: pkce, tkn: tkn, origin: origin))
        return try await self.authWithCode(code: code, pkce: pkce)
    }

    func authWithCode(code: String, pkce: Pkce? = nil) async throws -> AuthToken {
        let authCodeRequest = AuthCodeRequest(
            clientId: reachFiveApi.sdkConfig.clientId,
            code: code,
            redirectUri: reachFiveApi.sdkConfig.scheme,
            pkce: pkce
        )
        let token = try await reachFiveApi.authWithCode(authCodeRequest: authCodeRequest)
        return try AuthToken.fromOpenIdTokenResponse(token)
    }
}
