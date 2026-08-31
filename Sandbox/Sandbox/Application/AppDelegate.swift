import AuthenticationServices
import Foundation
import Reach5
import Reach5Facebook
import Reach5Google
import UIKit

#if targetEnvironment(macCatalyst)
// we don't add WeChat by default in order to be able to launch the app on mac Catalyst in order to test on local (more easily than with a simulator)
// Facebook itself provided a fix on the latest version apparently
// WeChat appears to just not be able to run on Catalyst at all
#else
    // Peut-être qu'un jour je serai capable de modifier les dépendance cocoapods par plateforme
    // https://betterprogramming.pub/why-dont-my-pods-compile-with-mac-catalyst-and-how-can-i-solve-it-ffc3fbec824e
    // Ce lien suggère une solution mais je ne vois pas les même choses dans Build Phases, je ne vois pas les dépendances Facebook et WeChat
    // import Reach5WeChat
#endif

// TODO:
// cf. wireframe de JC pour d'autres idées : https://miro.com/app/board/uXjVOMB0pG4=/
//   - notamment : affichage des jetons quand on est connecté et demande d'introspection
// Essayer d'améliorer la navigation pour qu'il n'y ait pas tous ces retours en arrière inutiles quand on navigue les onglets à la main
// Apparemment sur Mac Catalyst pour que le remplissage automatique des mots de passe fonctionne il faut mettre "l'appid" dans apple-app-site-association. cf. https://developer.apple.com/videos/play/wwdc2019/516?time=289
// register for revocation notification dans l'app (https://developer.apple.com/videos/play/wwdc2022/10122/?time=738)
// gérer l'upgrade d'un mot de passe vers SIWA ou mdp fort : https://developer.apple.com/videos/play/wwdc2020/10666
// synchroniser les règles de mdp de la console avec les password rules, à mettre dans la conf de l'app (https://developer.apple.com/videos/play/wwdc2020/10666?time=658)
// voir si les SMS 2FA sont auto-complétés

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    static let storage = SecureStorage()

    static let providers: [ProviderCreator] = [
        GoogleProvider(variant: "one_tap"),
        FacebookProvider(),
        AppleProvider(variant: "natif"),
        WebProvider(name: .bconnect, variant: "natif", mode: .customScheme),
    ]

    static let internalConfig = SdkInternalConfig(loggingEnabled: true)

    /// Built on first use, and rebuilt by ``switchEnvironment(to:)`` — the environment is a runtime choice
    /// now, so the instance cannot be a stored constant decided at compile time.
    private lazy var builtReachFive: ReachFive = makeReachFive()

    var reachfive: ReachFive {
        builtReachFive
    }

    @MainActor
    static func reachfive() -> ReachFive {
        let app = UIApplication.shared.delegate as! AppDelegate
        return app.reachfive
    }

    private func makeReachFive() -> ReachFive {
        let environment = SandboxEnvironment.selected
        print("ℹ️ ReachFive built on \(environment.label) (\(environment.domain))")
        let reachfive = ReachFive(
            sdkConfig: environment.sdkConfig,
            providersCreators: Self.providers,
            storage: Self.storage,
            sdkInternalConfig: Self.internalConfig
        )
        // Registered on the instance, not at launch: a rebuild would silently lose them otherwise, and the
        // passwordless and MFA screens would wait for a callback that can no longer arrive.
        registerCallbacks(on: reachfive)
        return reachfive
    }

    /// Rebuilds the SDK on another environment, and clears what belonged to the previous one.
    ///
    /// The token and the session cookies are the two things that would otherwise cross over: a single
    /// `SecureStorage` backs every instance, and `HTTPCookieStorage` is shared by the whole app. Anything else
    /// on screen keeps showing the old environment until its next call, which then fails on a missing token —
    /// acceptable in a sandbox, and cheaper than driving every controller back to its empty state.
    @MainActor
    func switchEnvironment(to environment: SandboxEnvironment) async {
        guard environment != SandboxEnvironment.selected else { return }

        Self.clearCookies(of: reachfive.sdkConfig.domain)
        Self.storage.removeToken()
        SandboxEnvironment.selected = environment
        builtReachFive = makeReachFive()
        await initializeReachFive()
    }

    private func registerCallbacks(on reachfive: ReachFive) {
        reachfive.addPasswordlessCallback { result in
            print("addPasswordlessCallback \(result)")
            NotificationCenter.default.post(name: .DidReceiveLoginCallback, object: nil, userInfo: ["result": result])
        }
        reachfive.addMfaCredentialRegistrationCallback { result in
            print("addMfaCredentialRegistrationCallback \(result)")
            NotificationCenter.default.post(name: .DidReceiveMfaVerifyEmail, object: nil, userInfo: ["result": result])
        }
        reachfive.addEmailVerificationCallback { result in
            print("addEmailVerificationCallback \(result)")
            NotificationCenter.default.post(name: .DidReceiveEmailVerificationCallback, object: nil, userInfo: ["result": result])
        }
    }

    /// Fetches the client configuration and refreshes the scopes the settings offer, the way the launch used
    /// to — a rebuilt instance starts with an empty scope list until this runs.
    private func initializeReachFive() async {
        do {
            _ = try await reachfive.initialize()
        } catch {
            print("initialize error \(error)")
        }
        SettingsViewController.selectedScopes = UserDefaults.standard.stringArray(forKey: "selectedScopes") ?? reachfive.scope
    }

    /// A domain-scoped cookie comes back dot-prefixed and case-folded, so compare host-suffix-wise — the same
    /// matching the settings screen uses to list them.
    private static func clearCookies(of domain: String) {
        let domain = domain.lowercased()
        HTTPCookieStorage.shared.cookies?
            .filter { cookie in
                let cookieDomain = cookie.domain.lowercased()
                return cookieDomain == domain || domain.hasSuffix(cookieDomain.hasPrefix(".") ? cookieDomain : ".\(cookieDomain)")
            }
            .forEach(HTTPCookieStorage.shared.deleteCookie)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        print("application:didFinishLaunchingWithOptions:\(launchOptions ?? [:])")

        Task {
            // The callbacks come with the instance now, registered by `makeReachFive()`.
            await self.initializeReachFive()

            if let window = self.window, let rootViewController = window.rootViewController {
                let defaults = UserDefaults.standard
                let selectedStartupActions = defaults.string(forKey: "selectedStartupAction")
                print("selectedStartupActions \(selectedStartupActions)")

                switch selectedStartupActions {
                case "Use refreshAccessToken at startup":
                    Task {
                        guard let token = Self.storage.getToken() else { return }
                        await rootViewController.handleAuthToken {
                            try await self.reachfive.refreshAccessToken(authToken: token)
                        }
                    }
                case "Use login with request at startup":
                    if #available(iOS 16, *) {
                        Task {
                            await rootViewController.handleLoginFlow {
                                let loginRequest = NativeLoginRequest(presenting: Presentation(from: rootViewController), scopes: SettingsViewController.selectedScopes, origin: #function)
                                return try await self.reachfive.login(withRequest: loginRequest, usingModalAuthorizationFor: [.Passkey, .Password, .SignInWithApple], display: .IfImmediatelyAvailableCredentials)
                            }
                        }
                    }
                default: break
                }
            }
        }

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        // Ceci est l'id tel que renvoyé par Apple dans idToken.sub ou AppleIDCredential.user
        appleIDProvider.getCredentialState(forUserID: "000707.3cc381460bce4bcc96e6fd5abdc1f121.1742") { credentialState, _ in
            switch credentialState {
            case .authorized: print("Apple Id state: authorized")
            case .revoked: print("Apple Id state: revoked")
            case .notFound: print("Apple Id state: not found")
            case .transferred: print("Apple Id state: transferred")
            default:
                break
            }
        }

        return reachfive.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        reachfive.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        reachfive.application(app, open: url, options: options)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        print("applicationWillResignActive")
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        print("applicationDidEnterBackground")
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        print("applicationWillEnterForeground")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        print("applicationDidBecomeActive")
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        reachfive.applicationDidBecomeActive(application)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        print("applicationWillTerminate")
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func applicationDidFinishLaunching(_ application: UIApplication) {
        print("applicationDidFinishLaunching")
    }

    func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        print("applicationProtectedDataWillBecomeUnavailable")
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        print("applicationProtectedDataDidBecomeAvailable")
    }
}

extension AppDelegate {
    static func withFreshToken<T>(potentiallyStale token: AuthToken, _ body: (_ refreshableToken: AuthToken) async throws -> T) async throws -> T {
        do {
            return try await body(token)
        } catch let ReachFiveError.AuthFailure(_, apiError) where apiError?.errorMessageKey == "error.accessToken.freshness" {
            // Automatically refresh the token if it is stale
            let freshToken = try await reachfive().refreshAccessToken(authToken: token)
            AppDelegate.storage.setToken(freshToken)
            return try await body(freshToken)
        }
    }
}

extension NSNotification.Name {
    static let DidReceiveLoginCallback = Notification.Name("DidReceiveLoginCallback")
    static let DidReceiveMfaVerifyEmail = Notification.Name("DidReceiveMfaVerifyEmail")
    static let DidReceiveEmailVerificationCallback = Notification.Name("DidReceiveEmailVerificationCallback")
}

extension UITableView {
    func dequeueDefaultReusableCell(withIdentifier identifier: String, for indexPath: IndexPath, text: String, secondaryText: String? = nil) -> UITableViewCell {
        let cell = dequeueReusableCell(withIdentifier: identifier, for: indexPath)

        var content = cell.defaultContentConfiguration()

        content.text = text
        content.secondaryText = secondaryText
        content.prefersSideBySideTextAndSecondaryText = true

        content.textProperties.font = UIFont.preferredFont(forTextStyle: .body)
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.textProperties.adjustsFontSizeToFitWidth = true

        content.secondaryTextProperties.font = UIFont.preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.adjustsFontSizeToFitWidth = true
        cell.contentConfiguration = content

        return cell
    }
}
