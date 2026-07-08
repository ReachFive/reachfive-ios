import Foundation
import AuthenticationServices

// Tous les callbacks d'ASAuthorizationController arrivent sur le main thread ; l'isolation @MainActor
// protège l'état mutable partagé entre les points d'entrée async et le delegate.
@MainActor
public class CredentialManager: NSObject {
    // nonisolated(unsafe) : affecté une seule fois depuis l'init nonisolated (appelé par ReachFive.init,
    // synchrone et hors main actor), jamais modifié ensuite. Lecture sans risque depuis le main actor.
    nonisolated(unsafe) let reachFiveApi: ReachFiveApi

    // MARK: - Contexte de requête

    // Les requêtes peuvent s'entrelacer (une requête modale peut démarrer pendant une requête auto-fill).
    // Tout l'état d'une requête vit donc dans un RequestContext indexé par son controller : chaque callback
    // du delegate retrouve le contexte de SA requête, et une requête ne peut pas écraser l'état d'une autre.
    private struct RequestContext {
        enum Pending {
            // signup, auto-fill, login non-discoverable
            case authToken(CheckedContinuation<AuthToken, Error>)
            // login modal (password/SIWA/passkey), qui peut déboucher sur un step-up MFA
            case loginFlow(CheckedContinuation<LoginFlow, Error>)
            // enregistrement d'une nouvelle clé (add/reset)
            case registration(CheckedContinuation<Void, Error>)
        }

        // retenu : maintient la requête système en vie jusqu'à sa complétion
        let controller: ASAuthorizationController
        // retenu fort pendant la durée de la requête : pas de cycle permanent, et le SDK
        // reste vivant jusqu'à la complétion (pas de back-pointer weak à dénuller)
        let reachFive: ReachFive
        let pending: Pending
        // anchor pour le presentationContextProvider
        let anchor: ASPresentationAnchor
        // le scope de la requête
        let scopes: [String]?
        // le scope tel qu'envoyé au serveur
        var scope: String? { scopes?.joined(separator: " ") }
        // origin optionnel pour les événements utilisateur
        let originR5: String?
        // données pour signup/register
        let passkeyCreationType: PasskeyCreationType?
        // le nonce pour Sign In With Apple
        let nonce: Pkce?
        let appleProvider: ConfiguredAppleProvider?

        func fail(with error: Error) {
            switch pending {
            case let .authToken(continuation): continuation.resume(throwing: error)
            case let .loginFlow(continuation): continuation.resume(throwing: error)
            case let .registration(continuation): continuation.resume(throwing: error)
            }
        }
    }

    // les requêtes en vol, indexées par leur controller
    private var contexts: [ObjectIdentifier: RequestContext] = [:]

    enum PasskeyCreationType {
        case Signup(signupOptions: RegistrationOptions)
        case AddPasskey(authToken: AuthToken)
        case ResetPasskey(resetOptions: ResetOptions)
    }

    // MARK: -

    // nonisolated : appelé depuis l'init synchrone de ReachFive, hors du main actor
    nonisolated init(reachFiveApi: ReachFiveApi) {
        self.reachFiveApi = reachFiveApi
    }

    // MARK: - Cycle de vie des requêtes

    /// Annule les requêtes en vol, principalement pour annuler une requête auto-fill avant de démarrer
    /// une requête modale (sinon cette dernière échouerait). Chaque annulation déclenche
    /// `didCompleteWithError(.canceled)` pour son controller, ce qui résout sa continuation en `.AuthCanceled`.
    private func cancelInFlightRequests() {
        guard #available(iOS 16.0, *) else { return } // cancel() n'existe qu'à partir d'iOS 16
        for context in contexts.values {
            context.controller.cancel()
        }
    }

    /// Crée le controller, enregistre le contexte de la requête PUIS lance la requête système via `perform` :
    /// comme tout se passe sur le main actor, la continuation est en place avant que le delegate puisse tirer.
    private func start(_ pending: RequestContext.Pending,
                       requests: [ASAuthorizationRequest],
                       reachFive: ReachFive,
                       anchor: ASPresentationAnchor,
                       scopes: [String]?,
                       originR5: String?,
                       passkeyCreationType: PasskeyCreationType? = nil,
                       nonce: Pkce? = nil,
                       appleProvider: ConfiguredAppleProvider? = nil,
                       perform: (ASAuthorizationController) -> Void) {
        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate = self
        controller.presentationContextProvider = self
        contexts[ObjectIdentifier(controller)] = RequestContext(controller: controller, reachFive: reachFive, pending: pending, anchor: anchor, scopes: scopes, originR5: originR5, passkeyCreationType: passkeyCreationType, nonce: nonce, appleProvider: appleProvider)
        perform(controller)
    }

    private func awaitAuthToken(requests: [ASAuthorizationRequest], reachFive: ReachFive, anchor: ASPresentationAnchor, scopes: [String]?, originR5: String?, passkeyCreationType: PasskeyCreationType? = nil, perform: (ASAuthorizationController) -> Void) async throws -> AuthToken {
        try await withCheckedThrowingContinuation { continuation in
            start(.authToken(continuation), requests: requests, reachFive: reachFive, anchor: anchor, scopes: scopes, originR5: originR5, passkeyCreationType: passkeyCreationType, perform: perform)
        }
    }

    private func awaitLoginFlow(requests: [ASAuthorizationRequest], reachFive: ReachFive, anchor: ASPresentationAnchor, scopes: [String]?, originR5: String?, nonce: Pkce? = nil, appleProvider: ConfiguredAppleProvider? = nil, perform: (ASAuthorizationController) -> Void) async throws -> LoginFlow {
        try await withCheckedThrowingContinuation { continuation in
            start(.loginFlow(continuation), requests: requests, reachFive: reachFive, anchor: anchor, scopes: scopes, originR5: originR5, nonce: nonce, appleProvider: appleProvider, perform: perform)
        }
    }

    private func awaitRegistration(requests: [ASAuthorizationRequest], reachFive: ReachFive, anchor: ASPresentationAnchor, originR5: String?, passkeyCreationType: PasskeyCreationType, perform: (ASAuthorizationController) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            start(.registration(continuation), requests: requests, reachFive: reachFive, anchor: anchor, scopes: nil, originR5: originR5, passkeyCreationType: passkeyCreationType, perform: perform)
        }
    }

    // MARK: - Signup
    @available(iOS 16.0, *)
    func signUp(withRequest request: SignupOptions, scopes: [String], anchor: ASPresentationAnchor, originR5: String? = nil, reachFive: ReachFive) async throws -> AuthToken {
        cancelInFlightRequests()

        let options = try await reachFiveApi.createWebAuthnSignupOptions(webAuthnSignupOptions: request)
        let registrationRequest = try makeCredentialRegistrationRequest(from: options, friendlyName: request.friendlyName)

        return try await awaitAuthToken(requests: [registrationRequest], reachFive: reachFive, anchor: anchor, scopes: scopes, originR5: originR5, passkeyCreationType: .Signup(signupOptions: options)) {
            $0.performRequests()
        }
    }

    // MARK: - Register
    @available(iOS 16.0, *)
    func registerNewPasskey(withRequest request: NewPasskeyRequest, authToken: AuthToken, reachFive: ReachFive) async throws {
        // Here it is very important to cancel a running auto-fill request, otherwise it will fail like other modal requests
        // so can't separate this method from the rest of the class
        cancelInFlightRequests()

        let options = try await reachFiveApi.createWebAuthnRegistrationOptions(authToken: authToken, registrationRequest: RegistrationRequest(origin: request.originWebAuthn!, friendlyName: request.friendlyName))
        let registrationRequest = try makeCredentialRegistrationRequest(from: options, friendlyName: request.friendlyName)

        try await awaitRegistration(requests: [registrationRequest], reachFive: reachFive, anchor: request.anchor, originR5: request.origin, passkeyCreationType: .AddPasskey(authToken: authToken)) {
            $0.performRequests()
        }
    }

    // MARK: - Reset
    @available(iOS 16.0, *)
    func resetPasskeys(withRequest request: ResetPasskeyRequest, reachFive: ReachFive) async throws {
        // Here it is very important to cancel a running auto-fill request, otherwise it will fail like other modal requests
        // so can't separate this method from the rest of the class
        cancelInFlightRequests()

        let resetOptions = ResetOptions(email: request.email, phoneNumber: request.phoneNumber, verificationCode: request.verificationCode, friendlyName: request.friendlyName, origin: request.originWebAuthn!, clientId: reachFiveApi.sdkConfig.clientId)
        let options = try await reachFiveApi.createWebAuthnResetOptions(resetOptions: resetOptions)
        let registrationRequest = try makeCredentialRegistrationRequest(from: options, friendlyName: request.friendlyName)

        try await awaitRegistration(requests: [registrationRequest], reachFive: reachFive, anchor: request.anchor, originR5: request.origin, passkeyCreationType: .ResetPasskey(resetOptions: resetOptions)) {
            $0.performRequests()
        }
    }

    // MARK: - Auto-fill
    @available(macCatalyst, unavailable)
    @available(iOS 16.0, *)
    func beginAutoFillAssistedPasskeySignIn(request: NativeLoginRequest, reachFive: ReachFive) async throws -> AuthToken {
        cancelInFlightRequests()

        let webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFiveApi.sdkConfig.clientId, origin: request.originWebAuthn!, scope: request.scopes)

        let assertionRequestOptions = try await reachFiveApi.createWebAuthnAuthenticationOptions(webAuthnLoginRequest: webAuthnLoginRequest)
        // Cette garde semble redondante (la méthode est déjà @available(iOS 16.0, *)) mais elle est nécessaire
        // pour compiler sous Xcode 26 (peut-être un bug Xcode). Ne pas la supprimer. Cf. commit 6a65a83.
        let authorizationRequest = if #available(iOS 16.0, *) {
            try createCredentialAssertionRequest(assertionRequestOptions)
        } else {
            throw ReachFiveError.TechnicalError(reason: "Passkey AutoFill-assisted sign-in requires iOS 16 or later.")
        }

        // AutoFill-assisted requests only support ASAuthorizationPlatformPublicKeyCredentialAssertionRequest.
        return try await awaitAuthToken(requests: [authorizationRequest], reachFive: reachFive, anchor: request.anchor, scopes: request.scopes, originR5: request.origin) {
            $0.performAutoFillAssistedRequests()
        }
    }

    // MARK: - Modal
    func login(withNonDiscoverableUsername username: Username, forRequest request: NativeLoginRequest, usingModalAuthorizationFor requestTypes: [NonDiscoverableAuthorization], display mode: Mode, reachFive: ReachFive) async throws -> AuthToken {
        cancelInFlightRequests()

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

        let built = try await buildAuthorizationRequests(webAuthnLoginRequest, authorizing: authzs) { assertionRequestOptions in
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

        return try await awaitAuthToken(requests: built.requests, reachFive: reachFive, anchor: request.anchor, scopes: request.scopes, originR5: request.origin) {
            performRequests(on: $0, mode: mode)
        }
    }

    func login(withRequest request: NativeLoginRequest, usingModalAuthorizationFor requestTypes: [ModalAuthorization], display mode: Mode, appleProvider: ConfiguredAppleProvider?, reachFive: ReachFive) async throws -> LoginFlow {
        cancelInFlightRequests()

        let webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFiveApi.sdkConfig.clientId, origin: request.originWebAuthn!, scope: request.scopes)

        let built = try await buildAuthorizationRequests(webAuthnLoginRequest, authorizing: requestTypes, appleProvider: appleProvider) { authenticationOptions in
            guard #available(iOS 16.0, *) else { // can't happen, because this is called from a >= iOS 16 context
                throw ReachFiveError.TechnicalError(reason: "Must be iOS 16 or higher")
            }
            return try self.createCredentialAssertionRequest(authenticationOptions)
        }

        return try await awaitLoginFlow(requests: built.requests, reachFive: reachFive, anchor: request.anchor, scopes: request.scopes, originR5: request.origin, nonce: built.nonce, appleProvider: built.appleProvider) {
            performRequests(on: $0, mode: mode)
        }
    }

    private struct BuiltRequests {
        let requests: [ASAuthorizationRequest]
        // renseignés uniquement si une requête Sign In With Apple fait partie du lot
        let nonce: Pkce?
        let appleProvider: ConfiguredAppleProvider?
    }

    /// Construit les `ASAuthorizationRequest` pour les types demandés, sans toucher à l'état de la classe.
    private func buildAuthorizationRequests(_ webAuthnLoginRequest: WebAuthnLoginRequest, authorizing requestTypes: [ModalAuthorization], appleProvider: ConfiguredAppleProvider? = nil, makeAuthorization: (AuthenticationOptions) throws -> ASAuthorizationRequest) async throws -> BuiltRequests {
        var requests: [ASAuthorizationRequest] = []
        var nonce: Pkce?
        var usedAppleProvider: ConfiguredAppleProvider?

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
                let siwaNonce = Pkce.generate()
                appleIDRequest.nonce = siwaNonce.codeChallenge
                nonce = siwaNonce
                usedAppleProvider = appleProvider

                requests.append(appleIDRequest)

            case .Passkey:
                do {
                    // Allow the user to use a saved passkey, if they have one.
                    let authOptions = try await self.reachFiveApi.createWebAuthnAuthenticationOptions(webAuthnLoginRequest: webAuthnLoginRequest)
                    let passkeyRequest = try makeAuthorization(authOptions)
                    requests.append(passkeyRequest)
                } catch let error where requestTypes.count > 1 {
                    // if there are other types of requests, do not block auth if only passkey fails. Just eat the error
                    Logger.shared.log("Passkey request error ignored in multi-type authorization: \(error)")
                }
            }
        }

        return BuiltRequests(requests: requests, nonce: nonce, appleProvider: usedAppleProvider)
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
    nonisolated public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // AuthenticationServices délivre ce callback sur le main thread
        MainActor.assumeIsolated {
            contexts[ObjectIdentifier(controller)]?.anchor ?? ASPresentationAnchor()
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension CredentialManager: ASAuthorizationControllerDelegate {

    nonisolated public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        // AuthenticationServices délivre ce callback sur le main thread
        MainActor.assumeIsolated {
            handleAuthorization(authorization, for: controller)
        }
    }

    nonisolated public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        // AuthenticationServices délivre ce callback sur le main thread
        MainActor.assumeIsolated {
            handleError(error, for: controller)
        }
    }

    // Retire le contexte à l'entrée du callback : garantit qu'une continuation est résolue exactement une fois,
    // et qu'un cancelInFlightRequests() ultérieur ne peut plus toucher une requête dont la complétion est en cours.
    private func takeContext(for controller: ASAuthorizationController) -> RequestContext? {
        contexts.removeValue(forKey: ObjectIdentifier(controller))
    }

    private func handleAuthorization(_ authorization: ASAuthorization, for controller: ASAuthorizationController) {
        guard let context = takeContext(for: controller) else {
            // controller inconnu ou requête déjà résolue : rien à faire
            return
        }

        Task { @MainActor in
            do {
                try await complete(authorization, context: context)
            } catch {
                context.fail(with: error)
            }
        }
    }

    private func complete(_ authorization: ASAuthorization, context: RequestContext) async throws {
        if let passwordCredential = authorization.credential as? ASPasswordCredential {
            // a password was selected to sign in
            guard case let .loginFlow(continuation) = context.pending else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: unexpected password credential for this request")
            }
            guard let scope = context.scope else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no scope")
            }

            let email: String?
            let phoneNumber: String?
            if passwordCredential.user.contains("@") {
                email = passwordCredential.user
                phoneNumber = nil
            } else {
                email = nil
                phoneNumber = passwordCredential.user
            }

            // Contrairement à ReachFive.loginWithPassword, origin n'est pas envoyé dans le LoginRequest
            // (divergence historique conservée telle quelle)
            let resp = try await reachFiveApi.loginWithPassword(loginRequest: LoginRequest(
                email: email,
                phoneNumber: phoneNumber,
                customIdentifier: nil, // No custom identifier for login because no custom identifier can be used for signup
                password: passwordCredential.password,
                grantType: "password",
                clientId: reachFiveApi.sdkConfig.clientId,
                scope: scope
            ))

            let loginFlow = try await context.reachFive.loginFlow(afterPasswordGrant: resp, scopes: context.scopes, origin: context.originR5)
            continuation.resume(returning: loginFlow)
        } else if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard case let .loginFlow(continuation) = context.pending else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: unexpected Sign In With Apple credential for this request")
            }
            guard let nonce = context.nonce, let scope = context.scope, let appleProvider = context.appleProvider else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no scope, no nonce, no apple provider")
            }

            guard let identityToken = appleIDCredential.identityToken else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no id token returned")
            }

            guard let idToken = String(data: identityToken, encoding: .utf8) else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: unreadable id token \(identityToken)")
            }

            let pkce = Pkce.generate()
            // Construction voisine mais distincte de ReachFive.buildAuthorizeURL (jambe OAuth différente :
            // id_token/nonce/noms Apple ici, state et URL de navigation là-bas) ; factoriser n'apporterait rien.
            let code = try await reachFiveApi.authorize(params: [
                "provider": appleProvider.providerConfig.providerWithVariant,
                "client_id": reachFiveApi.sdkConfig.clientId,
                "id_token": idToken,
                "response_type": "code",
                "redirect_uri": reachFiveApi.sdkConfig.redirectUri.absoluteString,
                "scope": scope,
                "code_challenge": pkce.codeChallenge,
                "code_challenge_method": pkce.codeChallengeMethod,
                "nonce": nonce.codeVerifier,
                "origin": context.originR5,
                "given_name": appleIDCredential.fullName?.givenName,
                "family_name": appleIDCredential.fullName?.familyName
            ])
            let token = try await context.reachFive.authWithCode(code: code, pkce: pkce)
            continuation.resume(returning: .AchievedLogin(authToken: token))
        } else if #available(iOS 16.0, *), let credentialRegistration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            // A new passkey was registered
            guard let attestationObject = credentialRegistration.rawAttestationObject else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no attestationObject")
            }

            let clientDataJSON = credentialRegistration.rawClientDataJSON
            let r5AuthenticatorAttestationResponse = R5AuthenticatorAttestationResponse(attestationObject: attestationObject.toBase64Url(), clientDataJSON: clientDataJSON.toBase64Url())

            let id = credentialRegistration.credentialID.toBase64Url()
            let registrationPublicKeyCredential = RegistrationPublicKeyCredential(id: id, rawId: id, type: "public-key", response: r5AuthenticatorAttestationResponse)

            guard let passkeyCreationType = context.passkeyCreationType else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no signupOptions")
            }

            switch passkeyCreationType {
            case let .AddPasskey(authToken):
                guard case let .registration(continuation) = context.pending else {
                    throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: unexpected passkey registration for this request")
                }
                try await reachFiveApi.registerWithWebAuthn(authToken: authToken, publicKeyCredential: registrationPublicKeyCredential, originR5: context.originR5)
                continuation.resume(returning: ())

            case let .Signup(signupOptions):
                guard case let .authToken(continuation) = context.pending else {
                    throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: unexpected passkey registration for this request")
                }
                guard context.scopes != nil else {
                    throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no scope")
                }

                let webauthnSignupCredential = WebauthnSignupCredential(webauthnId: signupOptions.options.publicKey.user.id, publicKeyCredential: registrationPublicKeyCredential)
                let authenticationToken = try await reachFiveApi.signupWithWebAuthn(webauthnSignupCredential: webauthnSignupCredential, originR5: context.originR5)
                let authToken = try await context.reachFive.loginCallback(tkn: authenticationToken.tkn, scopes: context.scopes, origin: context.originR5)
                continuation.resume(returning: authToken)

            case let .ResetPasskey(resetOptions):
                guard case let .registration(continuation) = context.pending else {
                    throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: unexpected passkey registration for this request")
                }
                let resetPublicKeyCredential = ResetPublicKeyCredential(resetOptions: resetOptions, publicKeyCredential: registrationPublicKeyCredential)
                try await reachFiveApi.resetWebAuthn(resetPublicKeyCredential: resetPublicKeyCredential, originR5: context.originR5)
                continuation.resume(returning: ())
            }
        } else if #available(iOS 16.0, *), let credentialAssertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            // A passkey was selected to sign in

            guard context.scopes != nil else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no scope")
            }

            let signature = credentialAssertion.signature.toBase64Url()
            let clientDataJSON = credentialAssertion.rawClientDataJSON.toBase64Url()
            let userID = credentialAssertion.userID.toBase64Url()

            let id = credentialAssertion.credentialID.toBase64Url()
            let authenticatorData = credentialAssertion.rawAuthenticatorData.toBase64Url()
            let response = R5AuthenticatorAssertionResponse(authenticatorData: authenticatorData, clientDataJSON: clientDataJSON, signature: signature, userHandle: userID)

            let authenticationToken = try await reachFiveApi.authenticateWithWebAuthn(authenticationPublicKeyCredential: AuthenticationPublicKeyCredential(id: id, rawId: id, type: "public-key", response: response))
            let authToken = try await context.reachFive.loginCallback(tkn: authenticationToken.tkn, scopes: context.scopes, origin: context.originR5)

            switch context.pending {
            case let .authToken(continuation):
                continuation.resume(returning: authToken)
            case let .loginFlow(continuation):
                continuation.resume(returning: .AchievedLogin(authToken: authToken))
            case .registration:
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: unexpected passkey assertion for this request")
            }
        } else {
            throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: Received unknown authorization type.")
        }
    }

    private func handleError(_ error: Error, for controller: ASAuthorizationController) {
        guard let context = takeContext(for: controller) else {
            // controller inconnu ou requête déjà résolue : rien à faire
            return
        }

        context.fail(with: Self.adapt(error))
    }

    // Fonction pure, extraite pour être testable unitairement
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

// MARK: - utilities
extension CredentialManager {
    /// Construit une requête d'enregistrement de passkey à partir des options renvoyées par le serveur.
    /// Pendant symétrique de ``createCredentialAssertionRequest(_:)``. Internal pour être testable.
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
}
