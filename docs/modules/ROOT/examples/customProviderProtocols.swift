public protocol ProviderCreator {
    var name: String { get }
    var variant: String? { get }

    func create(reachFive: ReachFive, providerConfig: ProviderConfig, clientConfigResponse: ClientConfigResponse) -> Provider
}

public protocol Provider {
    var name: String { get }
    func login(scope: [String]?, origin: String, presenting: Presentation) async throws -> AuthToken
    func logout() async throws

    // Default (no-op) implementations provided — override only what your provider needs:
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    func applicationDidBecomeActive(_ application: UIApplication)
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool
}
