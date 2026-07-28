import AuthenticationServices
import Foundation

/// Les deux protocoles d'ASAuthorizationController (delegate et presentationContextProvider) sont annotés
/// NS_SWIFT_UI_ACTOR : leurs callbacks arrivent donc sur le main actor, et l'isolation @MainActor de la
/// classe protège l'état mutable partagé entre les points d'entrée async et ces callbacks.
@MainActor
class CredentialManager: NSObject {
    // MARK: - Contexte de requête

    /// Les requêtes peuvent se chevaucher : une nouvelle requête annule celles en cours, mais le callback
    /// système d'une requête annulée peut encore arriver après. Tout l'état d'une requête vit donc dans un
    /// RequestContext indexé par son controller : chaque callback retrouve le contexte de sa requête, et
    /// une requête ne peut pas écraser l'état d'une autre.
    private struct RequestContext {
        /// retenu : maintient la requête système en vie jusqu'à sa complétion
        let controller: ASAuthorizationController
        /// anchor pour le presentationContextProvider
        let anchor: ASPresentationAnchor
        /// continuation de l'appelant, reprise exactement une fois : toute reprise passe par le retrait
        /// du contexte du dictionnaire, et seul le retrait qui réussit reprend la continuation
        let continuation: CheckedContinuation<ASAuthorization, Error>
    }

    /// Données d'un Sign In With Apple, à conserver entre la construction de la requête et sa complétion.
    struct SignInWithApple {
        let nonce: Pkce
        let provider: ConfiguredAppleProvider
    }

    /// les requêtes en cours, indexées par leur controller
    private var contexts: [ObjectIdentifier: RequestContext] = [:]

    /// nonisolated : appelé depuis l'init synchrone de ReachFive, hors du main actor
    override nonisolated init() {}

    // MARK: - Cycle de vie des requêtes

    /// Soumet une requête système et rend l'autorisation obtenue. Le post-traitement (validation serveur,
    /// échange de jeton) reste dans la tâche de l'appelant, qui garde donc la main sur son annulation et
    /// sur ses erreurs, et chaque flux se lit d'un seul tenant à son point d'entrée.
    ///
    /// Le contexte est enregistré avant la soumission : comme tout se passe sur le main actor, la
    /// continuation est en place avant que le delegate puisse tirer.
    ///
    /// Internal pour être testable : un test pilote la méthode avec un `submit` inerte (la requête n'est
    /// jamais soumise au système) puis simule les callbacks du delegate.
    func perform(
        requests: [ASAuthorizationRequest],
        anchor: ASPresentationAnchor,
        using submit: (ASAuthorizationController) -> Void
    ) async throws -> ASAuthorization {
        guard !requests.isEmpty else {
            // ASAuthorizationController exige au moins une requête. Sans cette garde, le système ne
            // rappellerait jamais le delegate et l'appelant resterait suspendu indéfiniment.
            throw ReachFiveError.TechnicalError(reason: "No authorization request to perform")
        }

        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate = self
        controller.presentationContextProvider = self
        let key = ObjectIdentifier(controller)

        return try await withTaskCancellationHandler {
            // La tâche appelante peut avoir été annulée avant même d'arriver ici : ne rien soumettre.
            try Task.checkCancellation()

            return try await withCheckedThrowingContinuation { continuation in
                // Annulation des requêtes en cours et soumission de la nouvelle dans le même bloc
                // synchrone : aucune autre tâche du main actor ne peut s'exécuter entre les deux.
                cancelInFlightRequests()
                contexts[key] = RequestContext(controller: controller, anchor: anchor, continuation: continuation)
                submit(controller)
            }
        } onCancel: {
            // onCancel est appelé hors du main actor ; on y repasse pour toucher `contexts`. Le saut de
            // tâche ne peut pas devancer l'enregistrement du contexte : le bloc ci-dessus ne rend la main
            // au main actor qu'après la soumission.
            Task { @MainActor in self.cancelBecauseCallerWasCancelled(key) }
        }
    }

    /// Annule les requêtes en cours, principalement pour annuler une requête auto-fill avant de démarrer
    /// une requête modale (sinon cette dernière échouerait).
    ///
    /// La continuation de chaque requête annulée est reprise ici en `.AuthCanceled`, sans attendre le
    /// `didCompleteWithError(.canceled)` du système : celui-ci n'est promis que si un flux tournait
    /// effectivement (cf. la doc de `ASAuthorizationController.cancel()`), et une requête dont le système
    /// ne rappelle jamais laisserait son appelant suspendu et son contexte en mémoire pour toujours. Le
    /// callback tardif éventuel ne trouve plus de contexte et est ignoré.
    ///
    /// Appelé par ``perform(requests:anchor:using:)`` dans le même bloc synchrone que la soumission de la
    /// nouvelle requête : l'application ne peut donc pas relancer une requête auto-fill — sa réaction
    /// habituelle à `.AuthCanceled` — avant que la nouvelle requête ne soit soumise.
    ///
    /// Internal pour être testable.
    func cancelInFlightRequests() {
        let inFlight = Array(contexts.values)
        contexts.removeAll()
        for context in inFlight {
            if #available(iOS 16.0, *) { // cancel() n'existe qu'à partir d'iOS 16
                context.controller.cancel()
            }
            context.continuation.resume(throwing: ReachFiveError.AuthCanceled)
        }
    }

    /// Reprend la requête `key` en `CancellationError` parce que la tâche appelante a été annulée, et
    /// arrête la requête système. Volontairement pas `.AuthCanceled` : cette erreur signale une annulation
    /// par l'utilisateur, à laquelle les applications réagissent en relançant une requête auto-fill, alors
    /// qu'ici c'est l'écran appelant qui disparaît.
    private func cancelBecauseCallerWasCancelled(_ key: ObjectIdentifier) {
        guard let context = contexts.removeValue(forKey: key) else {
            // requête déjà complétée ou jamais enregistrée : rien à faire
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

        // request.scope est déjà le join espace de la liste de scopes (cf. SignupOptions) ; on la retrouve
        // sans dupliquer la valeur en paramètre, un token de scope OAuth ne pouvant pas contenir d'espace.
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

    /// La seule requête possible ici est une assertion restreinte aux credentials que le serveur associe
    /// au username : il n'y a pas de lot à assembler, le flux construit sa requête lui-même.
    ///
    /// Volontairement sans annotation `@available`, contrairement aux autres flux passkey : `.Passkey` est
    /// le seul cas de `NonDiscoverableAuthorization` aujourd'hui, mais une assertion de clé de sécurité
    /// existe dès iOS 15 et serait un second cas ici — cette méthode et
    /// ``authenticate(with:scopes:reachFive:originR5:)`` sont écrites pour que l'ajouter ne demande pas de
    /// relever la version minimale de ce flux.
    func login(withNonDiscoverableUsername username: Username, forRequest request: ResolvedNativeLoginRequest, usingModalAuthorizationFor requestTypes: [NonDiscoverableAuthorization], display mode: Mode, reachFive: ReachFive) async throws -> AuthToken {
        let options = try await reachFive.reachFiveApi.createWebAuthnAuthenticationOptions(
            webAuthnLoginRequest: makeWebAuthnLoginRequest(for: request, username: username, reachFive: reachFive)
        )

        // Une requête par type demandé, toutes construites sur les mêmes options serveur. Le compte est
        // connu ici, donc chaque requête est restreinte aux credentials que le serveur lui associe.
        var requests: [ASAuthorizationRequest] = []
        for type in requestTypes {
            switch type {
            case .Passkey:
                // `.Passkey` n'est pas constructible sous iOS 16, donc cette branche ne s'exécute jamais
                // ailleurs — la garde est pour le compilateur, qui ne peut pas le savoir.
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
        var passkey: Result<ASAuthorizationRequest, Error>?
        if #available(iOS 16.0, *), requestTypes.contains(.Passkey) {
            do {
                let options = try await reachFive.reachFiveApi.createWebAuthnAuthenticationOptions(
                    webAuthnLoginRequest: makeWebAuthnLoginRequest(for: request, reachFive: reachFive)
                )
                passkey = try .success(makePasskeyAssertionRequest(options, restrictedToAllowedCredentials: false))
            } catch {
                passkey = .failure(error)
            }
        }

        let built = try buildAuthorizationRequests(authorizing: requestTypes, appleProvider: appleProvider, passkey: passkey)

        let authorization = try await perform(requests: built.requests, anchor: request.anchor) {
            performRequests(on: $0, mode: mode)
        }

        return try await completeModalLogin(authorization, scopes: request.scopes, siwa: built.siwa, reachFive: reachFive, originR5: request.origin)
    }

    /// Internal pour être testable
    struct BuiltRequests {
        let requests: [ASAuthorizationRequest]
        /// renseigné si une requête Sign In With Apple fait partie du lot
        let siwa: SignInWithApple?
    }

    /// Assemble le lot de requêtes de la connexion modale, dans l'ordre demandé — le système présente les
    /// credentials dans cet ordre. Fonction pure : aucun réseau, aucun état de la classe.
    ///
    /// - Parameter passkey: la requête d'assertion déjà construite par l'appelant, ou l'erreur rencontrée
    ///   en la construisant ; nil si `.Passkey` n'a pas été demandé.
    ///
    /// Internal pour être testable.
    func buildAuthorizationRequests(
        authorizing requestTypes: [ModalAuthorization],
        appleProvider: ConfiguredAppleProvider?,
        passkey: Result<ASAuthorizationRequest, Error>?
    ) throws -> BuiltRequests {
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
                if let appleProvider {
                    siwa = SignInWithApple(nonce: siwaNonce, provider: appleProvider)
                }

                requests.append(appleIDRequest)

            case .Passkey:
                guard let passkey else { break }
                do {
                    // Allow the user to use a saved passkey, if they have one.
                    try requests.append(passkey.get())
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
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let anchor = contexts[ObjectIdentifier(controller)]?.anchor else {
            // Ne devrait pas arriver : le contexte est enregistré avant la soumission de la requête et
            // retiré à sa complétion. Une fenêtre détachée vaut mieux qu'un crash, mais elle serait
            // invisible à l'écran : on la signale.
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

    /// Retire le contexte à l'entrée du callback : garantit qu'une continuation est résolue exactement une
    /// fois (un second callback pour le même controller ne trouve plus rien), et qu'une annulation
    /// ultérieure ne peut plus toucher une requête déjà complétée.
    private func takeContext(for controller: ASAuthorizationController) -> RequestContext? {
        contexts.removeValue(forKey: ObjectIdentifier(controller))
    }

    /// Fonction pure, extraite pour être testable unitairement
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

// MARK: - exploitation des credentials reçus

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

    /// Extrait l'assertion WebAuthn d'une autorisation, la valide auprès du serveur et rend le jeton.
    /// Partagé par la connexion par passkey (auto-fill / non-discoverable) et la branche passkey de la
    /// connexion modale. Lève une erreur technique si l'autorisation n'est pas une assertion WebAuthn.
    ///
    /// Typée sur ``ASAuthorizationPublicKeyCredentialAssertion`` et non sur le credential de plateforme :
    /// le protocole déclare tous les champs qu'on lit, et une assertion de clé de sécurité s'y conforme
    /// aussi, donc supporter les clés de sécurité ne touchera pas cette méthode.
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

    /// Complète une connexion modale, seul flux à pouvoir recevoir plusieurs types de credential
    /// (mot de passe, Sign In With Apple ou passkey).
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

// MARK: - construction des requêtes

extension CredentialManager {
    /// Le socle commun aux trois flux de connexion WebAuthn.
    private func makeWebAuthnLoginRequest(for request: ResolvedNativeLoginRequest, username: Username? = nil, reachFive: ReachFive) -> WebAuthnLoginRequest {
        WebAuthnLoginRequest(clientId: reachFive.sdkConfig.clientId, origin: request.originWebAuthn, username: username, scope: request.scopes)
    }

    /// Construit une requête d'enregistrement de passkey à partir des options renvoyées par le serveur.
    /// Pendant symétrique de ``makePasskeyAssertionRequest(_:restrictedToAllowedCredentials:)``.
    ///
    /// `friendlyName` est celui demandé par l'application, et non `options.friendlyName` : rien ne garantit
    /// que le serveur renvoie la valeur qu'on lui a passée, et c'est bien l'intention de l'application qui
    /// doit nommer la passkey dans le trousseau.
    ///
    /// Internal pour être testable.
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

    /// Construit une requête d'assertion de passkey à partir des options renvoyées par le serveur.
    ///
    /// - Parameter restrictedToAllowedCredentials: restreint la requête aux credentials listés par le
    ///   serveur — ce que fait la connexion non-discoverable, qui sait de quel compte il s'agit. L'auto-fill
    ///   et la connexion modale laissent au contraire l'utilisateur choisir parmi ses passkeys.
    ///
    /// Ce sont les appelants qui portent la garde de disponibilité : `.Passkey` n'étant pas constructible
    /// sous iOS 16, sa présence dans une demande implique déjà iOS 16 à l'exécution.
    ///
    /// Internal pour être testable.
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
