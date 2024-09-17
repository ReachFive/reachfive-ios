import Foundation
import BrightFutures

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
        return credentialManager.login(withRequest: NativeLoginRequest(anchor: window, originWebAuthn: "https://\(sdkConfig.domain)", scopes: scope, origin: origin), usingModalAuthorizationFor: [.SignInWithApple], display: .Always, appleProvider: self)
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
