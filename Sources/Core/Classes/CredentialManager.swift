import Foundation
import AuthenticationServices

// Tous les callbacks d'ASAuthorizationController arrivent sur le main thread ; l'isolation @MainActor
// protège l'état mutable partagé entre les points d'entrée async et le delegate.
@MainActor
public class CredentialManager: NSObject {
    // MARK: - Contexte de requête

    // Les requêtes peuvent s'entrelacer (une requête modale peut démarrer pendant une requête auto-fill).
    // Tout l'état d'une requête vit donc dans un RequestContext indexé par son controller : chaque callback
    // du delegate retrouve le contexte de SA requête, et une requête ne peut pas écraser l'état d'une autre.
    // Internal (et non private) pour que les tests puissent piloter perform(_:requests:...).
    struct RequestContext {
        // retenu : maintient la requête système en vie jusqu'à sa complétion
        let controller: ASAuthorizationController
        // retenu fort pendant la durée de la requête : pas de cycle permanent, et le SDK
        // reste vivant jusqu'à la complétion (pas de back-pointer weak à dénuller)
        let reachFive: ReachFive
        // anchor pour le presentationContextProvider
        let anchor: ASPresentationAnchor
        // origin optionnel pour les événements utilisateur
        let originR5: String?
        // l'opération demandée : continuation typée + données propres au flux
        let operation: Operation
    }

    /// L'opération portée par une requête. Chaque cas fixe d'un bloc le type de credential attendu, le
    /// traitement à appliquer et le type de valeur rendu par sa continuation : la nature de la requête
    /// est donc connue de façon univoque, sans avoir à recouper à la main un `Pending` et un `Extra` dans
    /// chaque branche de complétion. La continuation est le dernier associé, non étiqueté.
    enum Operation {
        /// Création de passkey à l'inscription → jeton d'authentification.
        case signup(options: RegistrationOptions, scopes: [String], CheckedContinuation<AuthToken, Error>)
        /// Enregistrement d'une passkey pour un compte déjà connecté (add) → rien.
        case addPasskey(authToken: AuthToken, CheckedContinuation<Void, Error>)
        /// Réinitialisation des passkeys → rien.
        case resetPasskey(options: ResetOptions, CheckedContinuation<Void, Error>)
        /// Connexion par assertion de passkey (auto-fill ou non-discoverable) → jeton d'authentification.
        case passkeyLogin(scopes: [String]?, CheckedContinuation<AuthToken, Error>)
        /// Connexion modale (mot de passe, Sign In With Apple ou passkey), pouvant déboucher sur un
        /// step-up MFA → LoginFlow. Seul flux à pouvoir recevoir plusieurs types de credential.
        case modalLogin(scopes: [String]?, siwa: SignInWithApple?, CheckedContinuation<LoginFlow, Error>)

        func fail(with error: Error) {
            switch self {
            case let .signup(_, _, continuation): continuation.resume(throwing: error)
            case let .addPasskey(_, continuation): continuation.resume(throwing: error)
            case let .resetPasskey(_, continuation): continuation.resume(throwing: error)
            case let .passkeyLogin(_, continuation): continuation.resume(throwing: error)
            case let .modalLogin(_, _, continuation): continuation.resume(throwing: error)
            }
        }
    }

    // Données d'un Sign In With Apple, à conserver entre la construction de la requête et sa complétion.
    struct SignInWithApple {
        let nonce: Pkce
        let provider: ConfiguredAppleProvider
    }

    // les requêtes en cours, indexées par leur controller
    private var contexts: [ObjectIdentifier: RequestContext] = [:]

    // nonisolated : appelé depuis l'init synchrone de ReachFive, hors du main actor
    nonisolated override init() {}

    // MARK: - Cycle de vie des requêtes

    /// Annule les requêtes en cours, principalement pour annuler une requête auto-fill avant de démarrer
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
    ///
    /// L'`Operation` à construire est passée comme closure recevant la continuation (`{ .signup(…, $0) }`),
    /// ce qui fixe le type de retour `T` de la requête. Internal pour être testable : un test pilote la méthode
    /// avec un `perform` inerte puis simule les callbacks du delegate.
    func perform<T>(
        _ makeOperation: (CheckedContinuation<T, Error>) -> Operation,
        requests: [ASAuthorizationRequest],
        reachFive: ReachFive,
        anchor: ASPresentationAnchor,
        originR5: String?,
        using perform: (ASAuthorizationController) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let controller = ASAuthorizationController(authorizationRequests: requests)
            controller.delegate = self
            controller.presentationContextProvider = self
            contexts[ObjectIdentifier(controller)] = RequestContext(controller: controller, reachFive: reachFive, anchor: anchor, originR5: originR5, operation: makeOperation(continuation))
            perform(controller)
        }
    }

    // MARK: - Signup
    @available(iOS 16.0, *)
    func signUp(withRequest request: SignupOptions, anchor: ASPresentationAnchor, originR5: String? = nil, reachFive: ReachFive) async throws -> AuthToken {
        cancelInFlightRequests()

        let options = try await reachFive.reachFiveApi.createWebAuthnSignupOptions(webAuthnSignupOptions: request)
        let registrationRequest = try makeCredentialRegistrationRequest(from: options, friendlyName: request.friendlyName)

        // request.scope est déjà le join espace de la liste de scopes (cf. SignupOptions) ; on la retrouve
        // sans dupliquer la valeur en paramètre, un token de scope OAuth ne pouvant pas contenir d'espace.
        let scopes = request.scope.components(separatedBy: " ")

        return try await perform({ .signup(options: options, scopes: scopes, $0) }, requests: [registrationRequest], reachFive: reachFive, anchor: anchor, originR5: originR5) {
            $0.performRequests()
        }
    }

    // MARK: - Register
    @available(iOS 16.0, *)
    func registerNewPasskey(withRequest request: NewPasskeyRequest, authToken: AuthToken, reachFive: ReachFive) async throws {
        // Here it is very important to cancel a running auto-fill request, otherwise it will fail like other modal requests
        // so can't separate this method from the rest of the class
        cancelInFlightRequests()

        let options = try await reachFive.reachFiveApi.createWebAuthnRegistrationOptions(authToken: authToken, registrationRequest: RegistrationRequest(origin: request.originWebAuthn!, friendlyName: request.friendlyName))
        let registrationRequest = try makeCredentialRegistrationRequest(from: options, friendlyName: request.friendlyName)

        try await perform({ .addPasskey(authToken: authToken, $0) }, requests: [registrationRequest], reachFive: reachFive, anchor: request.anchor, originR5: request.origin) {
            $0.performRequests()
        }
    }

    // MARK: - Reset
    @available(iOS 16.0, *)
    func resetPasskeys(withRequest request: ResetPasskeyRequest, reachFive: ReachFive) async throws {
        // Here it is very important to cancel a running auto-fill request, otherwise it will fail like other modal requests
        // so can't separate this method from the rest of the class
        cancelInFlightRequests()

        let resetOptions = ResetOptions(email: request.email, phoneNumber: request.phoneNumber, verificationCode: request.verificationCode, friendlyName: request.friendlyName, origin: request.originWebAuthn!, clientId: reachFive.sdkConfig.clientId)
        let options = try await reachFive.reachFiveApi.createWebAuthnResetOptions(resetOptions: resetOptions)
        let registrationRequest = try makeCredentialRegistrationRequest(from: options, friendlyName: request.friendlyName)

        try await perform({ .resetPasskey(options: resetOptions, $0) }, requests: [registrationRequest], reachFive: reachFive, anchor: request.anchor, originR5: request.origin) {
            $0.performRequests()
        }
    }

    // MARK: - Auto-fill
    @available(macCatalyst, unavailable)
    @available(iOS 16.0, *)
    func beginAutoFillAssistedPasskeySignIn(request: NativeLoginRequest, reachFive: ReachFive) async throws -> AuthToken {
        cancelInFlightRequests()

        let webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFive.sdkConfig.clientId, origin: request.originWebAuthn!, scope: request.scopes)

        let assertionRequestOptions = try await reachFive.reachFiveApi.createWebAuthnAuthenticationOptions(webAuthnLoginRequest: webAuthnLoginRequest)
        // Cette garde semble redondante (la méthode est déjà @available(iOS 16.0, *)) mais elle est nécessaire
        // pour compiler sous Xcode 26 (peut-être un bug Xcode). Ne pas la supprimer. Cf. commit 6a65a83.
        let authorizationRequest = if #available(iOS 16.0, *) {
            try createCredentialAssertionRequest(assertionRequestOptions)
        } else {
            throw ReachFiveError.TechnicalError(reason: "Passkey AutoFill-assisted sign-in requires iOS 16 or later.")
        }

        // AutoFill-assisted requests only support ASAuthorizationPlatformPublicKeyCredentialAssertionRequest.
        return try await perform({ .passkeyLogin(scopes: request.scopes, $0) }, requests: [authorizationRequest], reachFive: reachFive, anchor: request.anchor, originR5: request.origin) {
            $0.performAutoFillAssistedRequests()
        }
    }

    // MARK: - Modal
    func login(withNonDiscoverableUsername username: Username, forRequest request: NativeLoginRequest, usingModalAuthorizationFor requestTypes: [NonDiscoverableAuthorization], display mode: Mode, reachFive: ReachFive) async throws -> AuthToken {
        cancelInFlightRequests()

        let webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFive.sdkConfig.clientId, origin: request.originWebAuthn!, scope: request.scopes)
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

        let built = try await buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: authzs) { assertionRequestOptions in
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

        return try await perform({ .passkeyLogin(scopes: request.scopes, $0) }, requests: built.requests, reachFive: reachFive, anchor: request.anchor, originR5: request.origin) {
            performRequests(on: $0, mode: mode)
        }
    }

    func login(withRequest request: NativeLoginRequest, usingModalAuthorizationFor requestTypes: [ModalAuthorization], display mode: Mode, appleProvider: ConfiguredAppleProvider?, reachFive: ReachFive) async throws -> LoginFlow {
        cancelInFlightRequests()

        let webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFive.sdkConfig.clientId, origin: request.originWebAuthn!, scope: request.scopes)

        let built = try await buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: requestTypes, appleProvider: appleProvider) { authenticationOptions in
            guard #available(iOS 16.0, *) else { // can't happen, because this is called from a >= iOS 16 context
                throw ReachFiveError.TechnicalError(reason: "Must be iOS 16 or higher")
            }
            return try self.createCredentialAssertionRequest(authenticationOptions)
        }

        return try await perform({ .modalLogin(scopes: request.scopes, siwa: built.siwa, $0) }, requests: built.requests, reachFive: reachFive, anchor: request.anchor, originR5: request.origin) {
            performRequests(on: $0, mode: mode)
        }
    }

    // Internal pour être testable
    struct BuiltRequests {
        let requests: [ASAuthorizationRequest]
        // renseigné si une requête Sign In With Apple fait partie du lot
        let siwa: SignInWithApple?
    }

    /// Construit les `ASAuthorizationRequest` pour les types demandés, sans toucher à l'état de la classe.
    /// `fetchAuthenticationOptions` fait l'appel réseau par défaut ; un test peut le substituer pour
    /// construire les requêtes sans réseau.
    func buildAuthorizationRequests(_ webAuthnLoginRequest: WebAuthnLoginRequest, reachFive: ReachFive,authorizing requestTypes: [ModalAuthorization], appleProvider: ConfiguredAppleProvider? = nil, fetchAuthenticationOptions: (ReachFive, WebAuthnLoginRequest) async throws -> AuthenticationOptions = { try await $0.reachFiveApi.createWebAuthnAuthenticationOptions(webAuthnLoginRequest: $1) }, makeAuthorization: (AuthenticationOptions) throws -> ASAuthorizationRequest) async throws -> BuiltRequests {
        var requests: [ASAuthorizationRequest] = []
        var siwa: SignInWithApple? = nil

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
                if let appleProvider {
                    siwa = SignInWithApple(nonce: siwaNonce, provider: appleProvider)
                }

                requests.append(appleIDRequest)

            case .Passkey:
                do {
                    // Allow the user to use a saved passkey, if they have one.
                    let authOptions = try await fetchAuthenticationOptions(reachFive, webAuthnLoginRequest)
                    let passkeyRequest = try makeAuthorization(authOptions)
                    requests.append(passkeyRequest)
                } catch let error where requestTypes.count > 1 {
                    // if there are other types of requests, do not block auth if only passkey fails. Just eat the error
                    Logger.shared.log("Passkey request error ignored in multi-type authorization: \(error)")
                }
            }
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
                context.operation.fail(with: error)
            }
        }
    }

    /// Un seul `switch` sur l'opération : chaque branche sait quel credential elle attend et le récupère
    /// via un helper d'extraction. Plus aucun recoupement pending/extra/credential à faire à la main.
    private func complete(_ authorization: ASAuthorization, context: RequestContext) async throws {
        let reachFive = context.reachFive
        let reachFiveApi = reachFive.reachFiveApi

        switch context.operation {
        case let .signup(options, scopes, continuation):
            let credential = try registrationCredential(from: authorization)
            let webauthnSignupCredential = WebauthnSignupCredential(webauthnId: options.options.publicKey.user.id, publicKeyCredential: credential)
            let authenticationToken = try await reachFiveApi.signupWithWebAuthn(webauthnSignupCredential: webauthnSignupCredential, originR5: context.originR5)
            let authToken = try await reachFive.loginCallback(tkn: authenticationToken.tkn, scopes: scopes, origin: context.originR5)
            continuation.resume(returning: authToken)

        case let .addPasskey(authToken, continuation):
            let credential = try registrationCredential(from: authorization)
            try await reachFiveApi.registerWithWebAuthn(authToken: authToken, publicKeyCredential: credential, originR5: context.originR5)
            continuation.resume(returning: ())

        case let .resetPasskey(options, continuation):
            let credential = try registrationCredential(from: authorization)
            let resetPublicKeyCredential = ResetPublicKeyCredential(resetOptions: options, publicKeyCredential: credential)
            try await reachFiveApi.resetWebAuthn(resetPublicKeyCredential: resetPublicKeyCredential, originR5: context.originR5)
            continuation.resume(returning: ())

        case let .passkeyLogin(scopes, continuation):
            let authToken = try await authenticateWithPasskey(authorization, scopes: scopes, reachFive: reachFive, originR5: context.originR5)
            continuation.resume(returning: authToken)

        case let .modalLogin(scopes, siwa, continuation):
            let loginFlow = try await completeModalLogin(authorization, scopes: scopes, siwa: siwa, context: context)
            continuation.resume(returning: loginFlow)
        }
    }

    /// Complète une connexion modale, seul flux à pouvoir recevoir plusieurs types de credential
    /// (mot de passe, Sign In With Apple ou passkey).
    private func completeModalLogin(_ authorization: ASAuthorization, scopes: [String]?, siwa: SignInWithApple?, context: RequestContext) async throws -> LoginFlow {
        let reachFive = context.reachFive
        let reachFiveApi = reachFive.reachFiveApi
        let sdkConfig = reachFive.sdkConfig

        guard let scopes else {
            throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no scope")
        }

        if let passwordCredential = authorization.credential as? ASPasswordCredential {
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
                clientId: sdkConfig.clientId,
                scope: scopes.joined(separator: " "),
                origin: context.originR5
            ))

            return try await reachFive.loginFlow(afterPasswordGrant: resp, scopes: scopes, origin: context.originR5)
        } else if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let siwa else {
                throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no nonce, no apple provider")
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
                "provider": siwa.provider.providerConfig.providerWithVariant,
                "client_id": sdkConfig.clientId,
                "id_token": idToken,
                "response_type": "code",
                "redirect_uri": sdkConfig.redirectUri.absoluteString,
                "scope": scopes.joined(separator: " "),
                "code_challenge": pkce.codeChallenge,
                "code_challenge_method": pkce.codeChallengeMethod,
                "nonce": siwa.nonce.codeVerifier,
                "origin": context.originR5,
                "given_name": appleIDCredential.fullName?.givenName,
                "family_name": appleIDCredential.fullName?.familyName
            ])
            let token = try await reachFive.authWithCode(code: code, pkce: pkce)
            return .AchievedLogin(authToken: token)
        } else {
            // a passkey was selected to sign in
            let authToken = try await authenticateWithPasskey(authorization, scopes: scopes, reachFive: reachFive, originR5: context.originR5)
            return .AchievedLogin(authToken: authToken)
        }
    }

    private func handleError(_ error: Error, for controller: ASAuthorizationController) {
        guard let context = takeContext(for: controller) else {
            // controller inconnu ou requête déjà résolue : rien à faire
            return
        }

        context.operation.fail(with: Self.adapt(error))
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

// MARK: - extraction des credentials reçus
extension CredentialManager {
    /// Extrait le credential d'enregistrement de passkey d'une autorisation (signup / add / reset)
    /// et le convertit dans notre format. Lève une erreur technique si l'autorisation n'en contient pas.
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

    /// Extrait l'assertion de passkey d'une autorisation, la valide auprès du serveur et rend le jeton.
    /// Partagé par la connexion par passkey (auto-fill / non-discoverable) et la branche passkey de la
    /// connexion modale. Lève une erreur technique si l'autorisation n'est pas une assertion de passkey.
    private func authenticateWithPasskey(_ authorization: ASAuthorization, scopes: [String]?, reachFive: ReachFive, originR5: String?) async throws -> AuthToken {
        guard #available(iOS 16.0, *), let credentialAssertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: expected a passkey assertion")
        }
        guard let scopes else {
            throw ReachFiveError.TechnicalError(reason: "didCompleteWithAuthorization: no scope")
        }

        let signature = credentialAssertion.signature.toBase64Url()
        let clientDataJSON = credentialAssertion.rawClientDataJSON.toBase64Url()
        let userID = credentialAssertion.userID.toBase64Url()
        let id = credentialAssertion.credentialID.toBase64Url()
        let authenticatorData = credentialAssertion.rawAuthenticatorData.toBase64Url()
        let response = R5AuthenticatorAssertionResponse(authenticatorData: authenticatorData, clientDataJSON: clientDataJSON, signature: signature, userHandle: userID)

        let authenticationToken = try await reachFive.reachFiveApi.authenticateWithWebAuthn(authenticationPublicKeyCredential: AuthenticationPublicKeyCredential(id: id, rawId: id, type: "public-key", response: response))
        return try await reachFive.loginCallback(tkn: authenticationToken.tkn, scopes: scopes, origin: originR5)
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
