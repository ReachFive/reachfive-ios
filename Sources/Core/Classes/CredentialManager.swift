import Foundation
import AuthenticationServices
import BrightFutures

public class CredentialManager: NSObject {
    let reachFiveApi: ReachFiveApi

    // MARK: - these fields serve to remember the context between the start of a request and its completion
    // Do not erase them at the end of a request because requests can be interleaved (modal and auto-fill requests)

    // promise for authentification
    var promise: Promise<AuthToken, ReachFiveError>
    // promise for new key registration
    var registrationPromise: Promise<(), ReachFiveError>

    // anchor for presentationContextProvider
    var authenticationAnchor: ASPresentationAnchor?

    // the controller for the current request, to cancel it before starting a new request (mainly to cancel an auto-fill request when starting a modal request)
    var authController: ASAuthorizationController?

    // indicates whether the request is modal or auto-fill, in order to show a special error when the modal is canceled by the user
    var isPerformingModalReqest = false
    // data for signup/register
    var passkeyCreationType: PasskeyCreationType?
    // the scope of the request
    var scope: String?
    // optional origin for user events
    var originR5: String?
    // the nonce for Sign In With Apple
    var nonce: String?

    enum PasskeyCreationType {
        case Signup(signupOptions: RegistrationOptions)
        case AddPasskey(authToken: AuthToken)
        case ResetPasskey(resetOptions: ResetOptions)
    }

    // MARK: -

    public init(reachFiveApi: ReachFiveApi) {
        promise = Promise()
        registrationPromise = Promise()
        self.reachFiveApi = reachFiveApi
    }

    // MARK: - Signup
    @available(iOS 16.0, *)
    func signUp(withRequest request: SignupOptions, anchor: ASPresentationAnchor, originR5: String? = nil) -> Future<AuthToken, ReachFiveError> {
        authController?.cancel()
        promise = Promise()
        authenticationAnchor = anchor
        scope = request.scope
        self.originR5 = originR5

        reachFiveApi.createWebAuthnSignupOptions(webAuthnSignupOptions: request)
            .flatMap { options -> Result<ASAuthorizationRequest, ReachFiveError> in
                self.passkeyCreationType = .Signup(signupOptions: options)

                guard let challenge = options.options.publicKey.challenge.decodeBase64Url() else {
                    return .failure(.TechnicalError(reason: "unreadable challenge: \(options.options.publicKey.challenge)"))
                }

                guard let userID = options.options.publicKey.user.id.decodeBase64Url() else {
                    return .failure(.TechnicalError(reason: "unreadable userID from public key: \(options.options.publicKey.user.id)"))
                }

                let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.options.publicKey.rp.id)
                return .success(publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge, name: request.friendlyName, userID: userID))
            }
            .onSuccess { registrationRequest in
                let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
                authController.delegate = self
                authController.presentationContextProvider = self
                authController.performRequests()

                self.authController = authController
                self.isPerformingModalReqest = true
            }
            .onFailure { error in self.promise.failure(error) }

        return promise.future
    }

    // MARK: - Register
    @available(iOS 16.0, *)
    func registerNewPasskey(withRequest request: NewPasskeyRequest, authToken: AuthToken) -> Future<(), ReachFiveError> {
        // Here it is very important to cancel a running auti-fill request, otherwise it will fail like other modal requests
        // so can't separate this method from the rest of the class
        authController?.cancel()
        registrationPromise = Promise()
        authenticationAnchor = request.anchor
        self.originR5 = request.origin

        reachFiveApi.createWebAuthnRegistrationOptions(authToken: authToken, registrationRequest: RegistrationRequest(origin: request.originWebAuthn!, friendlyName: request.friendlyName))
            .flatMap { options -> Result<ASAuthorizationRequest, ReachFiveError> in
                self.passkeyCreationType = .AddPasskey(authToken: authToken)

                guard let challenge = options.options.publicKey.challenge.decodeBase64Url() else {
                    return .failure(.TechnicalError(reason: "unreadable challenge: \(options.options.publicKey.challenge)"))
                }

                guard let userID = options.options.publicKey.user.id.decodeBase64Url() else {
                    return .failure(.TechnicalError(reason: "unreadable userID from public key: \(options.options.publicKey.user.id)"))
                }

                let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.options.publicKey.rp.id)
                return .success(publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge, name: request.friendlyName, userID: userID))
            }
            .onSuccess { registrationRequest in
                let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
                authController.delegate = self
                authController.presentationContextProvider = self
                authController.performRequests()

                self.authController = authController
                self.isPerformingModalReqest = true
            }
            .onFailure { error in self.registrationPromise.failure(error) }

        return registrationPromise.future
    }

    // MARK: - Reset
    @available(iOS 16.0, *)
    func resetPasskeys(withRequest request: ResetPasskeyRequest) -> Future<(), ReachFiveError> {
        // Here it is very important to cancel a running auti-fill request, otherwise it will fail like other modal requests
        // so can't separate this method from the rest of the class
        authController?.cancel()
        registrationPromise = Promise()
        authenticationAnchor = request.anchor
        self.originR5 = request.origin

        let resetOptions = ResetOptions(email: request.email, phoneNumber: request.phoneNumber, verificationCode: request.verificationCode, friendlyName: request.friendlyName, origin: request.originWebAuthn!, clientId: reachFiveApi.sdkConfig.clientId)
        reachFiveApi.createWebAuthnResetOptions(resetOptions: resetOptions)
            .flatMap { options -> Result<ASAuthorizationRequest, ReachFiveError> in
                self.passkeyCreationType = .ResetPasskey(resetOptions: resetOptions)

                guard let challenge = options.options.publicKey.challenge.decodeBase64Url() else {
                    return .failure(.TechnicalError(reason: "unreadable challenge: \(options.options.publicKey.challenge)"))
                }

                guard let userID = options.options.publicKey.user.id.decodeBase64Url() else {
                    return .failure(.TechnicalError(reason: "unreadable userID from public key: \(options.options.publicKey.user.id)"))
                }

                let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.options.publicKey.rp.id)
                return .success(publicKeyCredentialProvider.createCredentialRegistrationRequest(challenge: challenge, name: request.friendlyName, userID: userID))
            }
            .onSuccess { registrationRequest in
                let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
                authController.delegate = self
                authController.presentationContextProvider = self
                authController.performRequests()

                self.authController = authController
                self.isPerformingModalReqest = true
            }
            .onFailure { error in self.registrationPromise.failure(error) }

        return registrationPromise.future
    }

    // MARK: - Auto-fill
    @available(macCatalyst, unavailable)
    @available(iOS 16.0, *)
    func beginAutoFillAssistedPasskeySignIn(request: NativeLoginRequest) -> Future<AuthToken, ReachFiveError> {
        authController?.cancel()
        promise = Promise()
        authenticationAnchor = request.anchor
        originR5 = request.origin

        let webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFiveApi.sdkConfig.clientId, origin: request.originWebAuthn!, scope: request.scopes)
        scope = webAuthnLoginRequest.scope

        reachFiveApi.createWebAuthnAuthenticationOptions(webAuthnLoginRequest: webAuthnLoginRequest)
            .flatMap(createCredentialAssertionRequest)
            .onSuccess { authorizationRequest in

                // AutoFill-assisted requests only support ASAuthorizationPlatformPublicKeyCredentialAssertionRequest.
                let authController = ASAuthorizationController(authorizationRequests: [authorizationRequest])
                authController.delegate = self
                authController.presentationContextProvider = self
                authController.performAutoFillAssistedRequests()
                self.authController = authController
                self.isPerformingModalReqest = false
            }
            .onFailure { error in self.promise.failure(error) }

        return promise.future
    }

    // MARK: - Modal
    func login(withNonDiscoverableUsername username: Username, forRequest request: NativeLoginRequest, usingModalAuthorizationFor requestTypes: [NonDiscoverableAuthorization], display mode: Mode) -> Future<AuthToken, ReachFiveError> {
        if #available(iOS 16.0, *) { authController?.cancel() }
        promise = Promise()
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

        return signInWith(webAuthnLoginRequest, withMode: mode, authorizing: authzs) { assertionRequestOptions in
            guard #available(iOS 16.0, *) else { // can't happen, because this is called from a >= iOS 16 context
                return .success(nil)
            }
            return self.createCredentialAssertionRequest(assertionRequestOptions)
                .flatMap { assertionRequest -> Result<ASAuthorizationRequest, ReachFiveError> in

                    guard let allowedCredentials = assertionRequestOptions.publicKey.allowCredentials else {
                        return .failure(.AuthFailure(reason: "no allowCredentials returned"))
                    }

                    let credentialIDs = allowedCredentials.compactMap { $0.id.decodeBase64Url() }
                    assertionRequest.allowedCredentials = credentialIDs.map(ASAuthorizationPlatformPublicKeyCredentialDescriptor.init(credentialID:))

                    return .success(assertionRequest)
                }
                .map { $0 }
        }
    }

    func login(withRequest request: NativeLoginRequest, usingModalAuthorizationFor requestTypes: [ModalAuthorization], display mode: Mode) -> Future<AuthToken, ReachFiveError> {
        if #available(iOS 16.0, *) { authController?.cancel() }
        promise = Promise()
        authenticationAnchor = request.anchor
        originR5 = request.origin

        let webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFiveApi.sdkConfig.clientId, origin: request.originWebAuthn!, scope: request.scopes)

        return signInWith(webAuthnLoginRequest, withMode: mode, authorizing: requestTypes) { authenticationOptions in
            guard #available(iOS 16.0, *) else { // can't happen, because this is called from a >= iOS 15 context
                return .success(nil)
            }
            return self.createCredentialAssertionRequest(authenticationOptions).map { $0 }
        }
    }

    private func signInWith(_ webAuthnLoginRequest: WebAuthnLoginRequest, withMode mode: Mode, authorizing requestTypes: [ModalAuthorization], makeAuthorization: @escaping (AuthenticationOptions) -> Result<ASAuthorizationRequest?, ReachFiveError>) -> Future<AuthToken, ReachFiveError> {
        scope = webAuthnLoginRequest.scope

        requestTypes.traverse { type -> Future<ASAuthorizationRequest?, ReachFiveError> in
                switch type {

                case .Password:
                    // Allow the user to use a saved password, if they have one.
                    let passwordRequest = ASAuthorizationPasswordProvider().createRequest()
                    return Future(value: passwordRequest)

                case .SignInWithApple:
                    // Allow the user to use a Sign In With Apple, if they have one.
                    let appleIDRequest = ASAuthorizationAppleIDProvider().createRequest()
                    appleIDRequest.requestedScopes = [.fullName, .email]
                    nonce = Pkce.generate().codeChallenge
                    appleIDRequest.nonce = nonce

                    return Future(value: appleIDRequest)

                case .Passkey:
                    // Allow the user to use a saved passkey, if they have one.
                    return reachFiveApi.createWebAuthnAuthenticationOptions(webAuthnLoginRequest: webAuthnLoginRequest)
                        .flatMap { makeAuthorization($0) }
                        // if there are other types of requests, do not block auth if passkey fails
                        .recoverWith { requestTypes.count != 1 ? Future(value: nil) : Future(error: $0) }
                }
            }
            .onSuccess { requests in
                let authController = ASAuthorizationController(authorizationRequests: requests.compactMap { $0 })
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
                self.isPerformingModalReqest = true
            }
            .onFailure { error in self.promise.failure(error) }

        return promise.future
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
        if let passwordCredential = authorization.credential as? ASPasswordCredential {
            guard let scope else {
                promise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: no scope"))
                return
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
            promise.completeWith(reachFiveApi.loginWithPassword(loginRequest: LoginRequest(
                    email: email,
                    phoneNumber: phoneNumber,
                    customIdentifier: nil, // No custom identifier for login because no custom identifier can be used for signup
                    password: passwordCredential.password,
                    grantType: "password",
                    clientId: reachFiveApi.sdkConfig.clientId,
                    scope: scope
                ))
                .flatMap({ self.loginCallback(tkn: $0.tkn, scope: scope) }))
        } else if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let nonce, let scope else {
                promise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: no scope, no nonce"))
                return
            }

            guard let identityToken = appleIDCredential.identityToken else {
                promise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: no id token returned"))
                return
            }

            guard let idToken = String(data: identityToken, encoding: .utf8) else {
                promise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: unreadable id token \(identityToken)"))
                return
            }

            print("appleIDCredential.user               \(appleIDCredential.user)")
            print("appleIDCredential.authorizedScopes   \(appleIDCredential.authorizedScopes)")
            print("appleIDCredential.state              \(appleIDCredential.state)")
            print("appleIDCredential.authorizationCode  \(appleIDCredential.authorizationCode)")
            print("appleIDCredential.email              \(appleIDCredential.email)")
            print("appleIDCredential.fullName           \(appleIDCredential.fullName)")
            print("appleIDCredential.realUserStatus     \(appleIDCredential.realUserStatus)")
            if #available(macCatalyst 17.0, *) {
                print("appleIDCredential.userAgeRange       \(appleIDCredential.userAgeRange)")
            }

            let pkce = Pkce.generate()
            promise.completeWith(reachFiveApi.authorize(params: [
                "provider": "apple",
                "client_id": reachFiveApi.sdkConfig.clientId,
                "id_token": idToken,
                "response_type": "code",
                "redirect_uri": reachFiveApi.sdkConfig.scheme,
                "scope": scope,
                "code_challenge": pkce.codeChallenge,
                "code_challenge_method": pkce.codeChallengeMethod,
                "nonce": nonce,
                "given_name": appleIDCredential.fullName?.givenName,
                "family_name": appleIDCredential.fullName?.familyName
            ]).flatMap({ self.authWithCode(code: $0) }))
        } else if #available(iOS 16.0, *), let credentialRegistration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            // A new passkey was registered
            guard let attestationObject = credentialRegistration.rawAttestationObject else {
                promise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: no attestationObject"))
                registrationPromise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: no attestationObject"))
                return
            }

            let clientDataJSON = credentialRegistration.rawClientDataJSON
            let r5AuthenticatorAttestationResponse = R5AuthenticatorAttestationResponse(attestationObject: attestationObject.toBase64Url(), clientDataJSON: clientDataJSON.toBase64Url())

            let id = credentialRegistration.credentialID.toBase64Url()
            let registrationPublicKeyCredential = RegistrationPublicKeyCredential(id: id, rawId: id, type: "public-key", response: r5AuthenticatorAttestationResponse)

            guard let passkeyCreationType else {
                promise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: no signupOptions"))
                registrationPromise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: no token"))
                return
            }

            switch passkeyCreationType {
            case let .AddPasskey(authToken):
                registrationPromise.completeWith(reachFiveApi.registerWithWebAuthn(authToken: authToken, publicKeyCredential: registrationPublicKeyCredential, originR5: self.originR5))

            case let .Signup(signupOptions):
                guard let scope else {
                    promise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: no scope"))
                    return
                }

                let webauthnSignupCredential = WebauthnSignupCredential(webauthnId: signupOptions.options.publicKey.user.id, publicKeyCredential: registrationPublicKeyCredential)
                promise.completeWith(reachFiveApi.signupWithWebAuthn(webauthnSignupCredential: webauthnSignupCredential, originR5: self.originR5)
                    .flatMap({ self.loginCallback(tkn: $0.tkn, scope: scope, origin: self.originR5) }))

            case let .ResetPasskey(resetOptions):
                let resetPublicKeyCredential = ResetPublicKeyCredential(resetOptions: resetOptions, publicKeyCredential: registrationPublicKeyCredential)
                registrationPromise.completeWith(reachFiveApi.resetWebAuthn(resetPublicKeyCredential: resetPublicKeyCredential, originR5: self.originR5))
            }
        } else if #available(iOS 16.0, *), let credentialAssertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            // A passkey was selected to sign in
            guard let scope else {
                promise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: no scope"))
                return
            }

            let signature = credentialAssertion.signature.toBase64Url()
            let clientDataJSON = credentialAssertion.rawClientDataJSON.toBase64Url()
            let userID = credentialAssertion.userID.toBase64Url()

            let id = credentialAssertion.credentialID.toBase64Url()
            let authenticatorData = credentialAssertion.rawAuthenticatorData.toBase64Url()
            let response = R5AuthenticatorAssertionResponse(authenticatorData: authenticatorData, clientDataJSON: clientDataJSON, signature: signature, userHandle: userID)

            promise.completeWith(reachFiveApi.authenticateWithWebAuthn(authenticationPublicKeyCredential: AuthenticationPublicKeyCredential(id: id, rawId: id, type: "public-key", response: response))
                .flatMap({ self.loginCallback(tkn: $0.tkn, scope: scope, origin: self.originR5) }))
        } else {
            promise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: Received unknown authorization type."))
            registrationPromise.tryFailure(.TechnicalError(reason: "didCompleteWithAuthorization: Received unknown authorization type."))
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let authorizationError = error as? ASAuthorizationError else {
            promise.tryFailure(.TechnicalError(reason: "\(error.localizedDescription)"))
            registrationPromise.tryFailure(.TechnicalError(reason: "\(error.localizedDescription)"))
            return
        }

        if authorizationError.code == .canceled {
            // Either the system doesn't find any credentials and the request ends silently, or the user cancels the request.
            // This is a good time to show a traditional login form, or ask the user to create an account.
            if isPerformingModalReqest {
                promise.tryFailure(.AuthCanceled)
                registrationPromise.tryFailure(.AuthCanceled)
            }
        } else {
            // Another ASAuthorization error.
            promise.tryFailure(.TechnicalError(reason: "\(error)"))
            registrationPromise.tryFailure(.TechnicalError(reason: "\(error)"))
        }
    }
}

// MARK: - utilities
extension CredentialManager {
    @available(iOS 16.0, *)
    private func createCredentialAssertionRequest(_ assertionRequestOptions: AuthenticationOptions) -> Result<ASAuthorizationPlatformPublicKeyCredentialAssertionRequest, ReachFiveError> {
        guard let challenge = assertionRequestOptions.publicKey.challenge.decodeBase64Url() else {
            return .failure(.TechnicalError(reason: "unreadable challenge: \(assertionRequestOptions.publicKey.challenge)"))
        }

        let publicKeyCredentialProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: assertionRequestOptions.publicKey.rpId)
        return .success(publicKeyCredentialProvider.createCredentialAssertionRequest(challenge: challenge))
    }

    private func adaptAuthz(_ nda: NonDiscoverableAuthorization) -> ModalAuthorization? {
        if #available(iOS 16.0, *), nda == .Passkey {
            return ModalAuthorization.Passkey
        }
        return nil
    }

    func loginCallback(tkn: String, scope: String, origin: String? = nil) -> Future<AuthToken, ReachFiveError> {
        let pkce = Pkce.generate()

        return reachFiveApi.loginCallback(loginCallback: LoginCallback(sdkConfig: reachFiveApi.sdkConfig, scope: scope, pkce: pkce, tkn: tkn, origin: origin))
            .flatMap({ self.authWithCode(code: $0, pkce: pkce) })
    }

    func authWithCode(code: String, pkce: Pkce? = nil) -> Future<AuthToken, ReachFiveError> {
        let authCodeRequest = AuthCodeRequest(
            clientId: reachFiveApi.sdkConfig.clientId,
            code: code,
            redirectUri: reachFiveApi.sdkConfig.scheme,
            pkce: pkce
        )
        return reachFiveApi
            .authWithCode(authCodeRequest: authCodeRequest)
            .flatMap({ AuthToken.fromOpenIdTokenResponseFuture($0) })
    }
}
