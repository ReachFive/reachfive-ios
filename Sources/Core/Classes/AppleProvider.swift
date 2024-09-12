import Foundation
import BrightFutures

//https://developer.apple.com/documentation/authenticationservices/implementing_user_authentication_with_sign_in_with_apple
//  et https://developer.apple.com/documentation/security/password_autofill/about_the_password_autofill_workflow
// ajout de la "capability" SIWA ✔︎
// au lancement de l'app : appleIDProvider.getCredentialState(forUserID) (4 cas dont transferred)
//      voir si ça ne se marche pas sur les pieds du refresh token (reco : 1 fois par jour)
// utiliser les state et nonce
// sur iOS 16, utiliser "prefersImmediatelyAvailableCredentials"
// register for revocation notification dans l'app (https://developer.apple.com/videos/play/wwdc2022/10122/?time=738)
// gérer l'upgrade d'un mot de passe vers SIWA ou mdp fort : https://developer.apple.com/videos/play/wwdc2020/10666
// côté serveur
//      Apple ID notif de changement (lien app-appleId supprimé depuis les settings, compte apple id carrément supprimé, private relay activé ou désactivé) https://developer.apple.com/videos/play/wwdc2020/10173?time=691
//      ajouter le well-known-change-password-url (wwdc2020/10666)
//      vérifier que l'on fait bien les bonnes vérification : signature, identityToken.iss="appleid.apple.com", identityToken.aud="bundle id", nonce, exp (https://developer.apple.com/videos/play/wwdc2022/10122/?time=540) ✔︎
//      utiliser realUserStatus
//      utiliser les refresh token d'Apple
//      suppression de compte (https://developer.apple.com/videos/play/wwdc2022/10122/?time=835)
// synchroniser les règles de mdp de la console avec les password rules, à mettre dans la conf de l'app (https://developer.apple.com/videos/play/wwdc2020/10666?time=658)
// voir si les SMS 2FA sont auto-complétés
// textContentType = .newPassword pour la création de compte ✔︎

class ConfiguredAppleProvider: NSObject, Provider {
    public static let NAME = "apple"
    let name: String = NAME

    let sdkConfig: SdkConfig
    let providerConfig: ProviderConfig
    let clientConfigResponse: ClientConfigResponse
    let credentialManager: CredentialManager

    public init(
        sdkConfig: SdkConfig,
        providerConfig: ProviderConfig,
        clientConfigResponse: ClientConfigResponse,
        credentialManager: CredentialManager
    ) {
        self.sdkConfig = sdkConfig
        self.providerConfig = providerConfig
        self.clientConfigResponse = clientConfigResponse
        self.credentialManager = credentialManager
    }

    public func login(
        scope: [String]?,
        origin: String,
        viewController: UIViewController?
    ) -> Future<AuthToken, ReachFiveError> {
        guard let window = viewController?.view.window else { fatalError("The view was not in the app's view hierarchy!") }
        let scope: [String] = scope ?? clientConfigResponse.scope.components(separatedBy: " ")
        return credentialManager.login(withRequest: NativeLoginRequest(anchor: window, originWebAuthn: "https://\(sdkConfig.domain)", scopes: scope, origin: origin), usingModalAuthorizationFor: [.SignInWithApple], display: .Always)
    }

    public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        true
    }

    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void) -> Bool {
        true
    }

    public func logout() -> Future<(), ReachFiveError> {
        Future(value: ())
    }

    override var description: String {
        "Provider: \(name)"
    }
}
