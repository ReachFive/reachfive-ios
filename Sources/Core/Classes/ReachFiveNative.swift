import Foundation
import AuthenticationServices
import BrightFutures

public extension ReachFive {
// On naming and signature for methods:
// first argument indicates modality to distinguish the two primary way UI is shown to user: Modal and AutoFill
// first argument label contains "with" instead of the method name in conformance to https://www.swift.org/documentation/api-design-guidelines/#give-prepositional-phrase-argument-label
// non-discoverable methods also take a requestType parameter even though there is only one such type:
//      1. to make it very clear that we are using passkeys
//      2. to be future proof. For non-discoverable, there is already Security Keys that exist and that we could support.
// AutoFill is @available(iOS 16.0, *) because ASAuthorizationController.performAutoFillAssistedRequests() itself is.
// The other methods control version availability with their respective Authorization enum to increase flexibility.
// For example the non-discoverable cannot be declared @available(iOS 16.0, *)
// because in the future we could support Security Keys, which are available since iOS 15

    /// Signup with a passkey
    @available(iOS 16.0, *)
    func signup(withRequest request: PasskeySignupRequest) -> Future<AuthToken, ReachFiveError> {
        let domain = sdkConfig.domain
        let signupOptions = SignupOptions(
            origin: request.originWebAuthn ?? "https://\(domain)",
            friendlyName: request.friendlyName,
            profile: request.passkeyProfile,
            clientId: sdkConfig.clientId,
            scope: request.scopes ?? scope
        )

        return credentialManager.signUp(withRequest: signupOptions, anchor: request.anchor, originR5: request.origin)
    }

    /// Starts an auto-fill assisted passkey login request.
    /// The passkey will be shown in the QuickType bar when selecting a field of content type Username.
    /// Start the request automatically early in the view lifecycle (e.g. in viewDidAppear), alone or in reaction to a modal request .IfImmediatelyAvailableCredentials that resulted in an .AuthCanceled.
    /// - Parameters:
    ///   - request: the anchor for the QuickType bar, plus scope and origin configuration
    /// - Returns: an AuthToken when the user was successfully logged in, or a ReachFiveError
    @available(macCatalyst, unavailable)
    @available(iOS 16.0, *)
    func beginAutoFillAssistedPasskeyLogin(withRequest request: NativeLoginRequest) -> Future<AuthToken, ReachFiveError> {
        credentialManager.beginAutoFillAssistedPasskeySignIn(request: adapt(request))
    }

    /// Signs in the user using credentials stored in the keychain, letting the system display all credentials available to choose from in a modal sheet.
    /// - Parameters:
    ///   - request: the anchor for the modal sheet, plus scope and origin configuration
    ///   - requestTypes: choose between Password and/or Passkey
    ///   - mode: choose the behavior when there are no credentials available
    /// - Returns: an AuthToken when the user was successfully logged in, ReachFiveError.AuthCanceled when the user cancelled the modal sheet or when there was no credentials available, or other kinds of ReachFiveError
    func login(withRequest request: NativeLoginRequest, usingModalAuthorizationFor requestTypes: [ModalAuthorization], display mode: Mode) -> Future<LoginFlow, ReachFiveError> {
        let appleProvider = providers.first { $0.name == AppleProvider.NAME } as? ConfiguredAppleProvider
        return credentialManager.login(withRequest: adapt(request), usingModalAuthorizationFor: requestTypes, display: mode, appleProvider: appleProvider)
    }

    /// Signs in the user using credentials stored in the keychain, letting the system display the credentials corresponding to the given username in a modal sheet.
    /// - Parameters:
    ///   - username: the username to log in the user with
    ///   - request: the anchor for the modal sheet, plus scope and origin configuration
    ///   - requestTypes: only passkey are supported for now
    ///   - mode: choose the behavior when there are no credentials available
    /// - Returns: an AuthToken when the user was successfully logged in, ReachFiveError.AuthCanceled when the user cancelled the modal sheet or when there was no credentials available, or other kinds of ReachFiveError
    func login(withNonDiscoverableUsername username: Username, forRequest request: NativeLoginRequest, usingModalAuthorizationFor requestTypes: [NonDiscoverableAuthorization], display mode: Mode) -> Future<AuthToken, ReachFiveError> {
        credentialManager.login(withNonDiscoverableUsername: username, forRequest: adapt(request), usingModalAuthorizationFor: requestTypes, display: mode)
    }

    /// Registers a new passkey for an existing user which currently has none in the keychain, or replace the existing passkey by a new one
    /// - Parameters:
    ///   - request: the anchor for the modal sheet, the friendlyName under which the passkey will be saved, and origin
    ///   - authToken: the token for the currently logged-in user
    /// - Returns: A ReachFiveError, or nothing when the Registration was successfull.
    @available(iOS 16.0, *)
    func registerNewPasskey(withRequest request: NewPasskeyRequest, authToken: AuthToken) -> Future<(), ReachFiveError> {
        let domain = sdkConfig.domain
        let originWebAuthn = request.originWebAuthn ?? "https://\(domain)"
        //TODO supprimer l'ancienne passkey du server
        return credentialManager.registerNewPasskey(withRequest: NewPasskeyRequest(anchor: request.anchor, friendlyName: request.friendlyName, originWebAuthn: originWebAuthn, origin: request.origin), authToken: authToken)
    }

    @available(iOS 16.0, *)
    func resetPasskeys(withRequest request: ResetPasskeyRequest) -> Future<(), ReachFiveError> {
        let domain = sdkConfig.domain
        let originWebAuthn = request.originWebAuthn ?? "https://\(domain)"
        return credentialManager.resetPasskeys(withRequest: ResetPasskeyRequest(verificationCode: request.verificationCode, friendlyName: request.friendlyName, anchor: request.anchor, email: request.email, phoneNumber: request.phoneNumber, originWebAuthn: originWebAuthn, origin: request.origin))
    }

    private func adapt(_ request: NativeLoginRequest) -> NativeLoginRequest {
        let domain = sdkConfig.domain
        let originWebAuthn = request.originWebAuthn ?? "https://\(domain)"
        let scopes = request.scopes ?? scope

        return NativeLoginRequest(anchor: request.anchor, originWebAuthn: originWebAuthn, scopes: scopes, origin: request.origin)
    }
}

public enum Username {
    case Unspecified(_ username: String)
    case Email(_ email: String)
    case PhoneNumber(_ phoneNumber: String)
}

public enum ModalAuthorization: Equatable {
    case Password
    case SignInWithApple
    @available(iOS 16.0, *)
    case Passkey
}

public enum NonDiscoverableAuthorization: Equatable {
    @available(iOS 16.0, *)
    case Passkey
}

/// The behavior of the modal sheet when there are no credential available.
public enum Mode: Equatable {
    /// If there are no locally saved credentials a modal will generally appear.
    ///
    /// Depending on the type of credential:
    /// - `.Passkey`: the system presents a QR code to allow signing in with a passkey from a nearby device.
    /// - `.SignInWithApple`: a signup sheet appears.
    /// - `.Password`: no UI appears.
    ///
    /// You can start this request in response to a user interaction.
    ///
    /// Corresponds to `AuthController.performRequests()`
    case Always
    /// If there are no locally saved credentials, no UI appears and the call ends in `ReachFiveError.AuthCanceled`.
    ///
    /// You can start a request automatically early in the view lifecycle (e.g. in `viewDidAppear`) or at app launch.
    ///
    /// Corresponds to `AuthController.performRequests(options: .preferImmediatelyAvailableCredentials)`
    @available(iOS 16.0, *)
    case IfImmediatelyAvailableCredentials
}
