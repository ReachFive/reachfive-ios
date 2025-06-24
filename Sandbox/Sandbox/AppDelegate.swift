import AuthenticationServices

import Foundation
import Reach5
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

//TODO
// Mettre une nouvelle page dans une quatrième tabs ou dans l'app réglages:
// - Paramétrage : scopes, origin, utilisation du refresh au démarage ?
// cf. wireframe de JC pour d'autres idées : https://miro.com/app/board/uXjVOMB0pG4=/
// Pouvoir sélectionner entre plusieurs confs ReachFive
// - d'abord en dur ici et dans les entitlements. Sélectionner la bonne dans le let reachfive: ReachFive =
// - ensuite en choisir une avec Xcode Custom Environment Variables : https://derrickho328.medium.com/xcode-custom-environment-variables-681b5b8674ec
// - voir à la volée directement dans l'app ou dans une section de l'app réglages
// - Indiquer sur quel environnement on est connecté en l'affichant en titre de la page des fonctions
// Essayer d'améliorer la navigation pour qu'il n'y ait pas tous ces retours en arrière inutiles quand on navigue les onglets à la main
// Mettre la version des SDK en tant que version de la Sandbox (vérif : User Agent Alamofire des user events)
// Mettre un bouton recharger conf (lancer initialize) pour si la conf backend a changé
// Apparemment sur Mac Catalyst pour que le remplissage automatique des mots de passe fonctionne il faut mettre "l'appid" dans apple-app-site-association. cf. https://developer.apple.com/videos/play/wwdc2019/516?time=289
// register for revocation notification dans l'app (https://developer.apple.com/videos/play/wwdc2022/10122/?time=738)
// gérer l'upgrade d'un mot de passe vers SIWA ou mdp fort : https://developer.apple.com/videos/play/wwdc2020/10666
// synchroniser les règles de mdp de la console avec les password rules, à mettre dans la conf de l'app (https://developer.apple.com/videos/play/wwdc2020/10666?time=658)
// voir si les SMS 2FA sont auto-complétés

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    public static let storage = SecureStorage()

    /// La reco pour la redirectURI de [https://datatracker.ietf.org/doc/html/rfc8252#section-7.1](RFC 8252) est:
    /// - apps MUST use a URI scheme based on a domain name under their control, expressed in reverse order, as recommended by Section 3.8 of [RFC7595] for private-use URI schemes
    /// - Following the requirements of Section 3.2 of [RFC3986], as there is no naming authority for private-use URI scheme redirects, only a single slash ("/") appears after the scheme component.
    ///
    /// A complete example of a redirect URI utilizing a private-use URI scheme is:
    ///
    ///     com.example.app:/oauth2redirect/example-provider
    static let sdkLocal = SdkConfig(
        domain: "local-sandbox.og4.me",
        clientId: "9DKRdQyDLpaJqQQQAR9K"
    )

    static let sdkRemote = SdkConfig(
        domain: "integ-qa-fonctionnelle.reach5.net",
        clientId: "9DKRdQyDLpaJqQQQAR9K"
    )

    static let providers: [ProviderCreator] = [/*GoogleProvider(variant: "one_tap"), FacebookProvider(),*/ AppleProvider(variant: "natif")]
    #if targetEnvironment(macCatalyst)
    static let macLocal: ReachFive = ReachFive(sdkConfig: sdkLocal, providersCreators: providers, storage: storage)
    static let macRemote: ReachFive = ReachFive(sdkConfig: sdkRemote, providersCreators: providers, storage: storage)
    let reachfive = macLocal
    #else
    static let local: ReachFive = ReachFive(sdkConfig: sdkLocal, providersCreators: providers, storage: storage)
    static let remote: ReachFive = ReachFive(sdkConfig: sdkRemote, providersCreators: providers, storage: storage)
    #if targetEnvironment(simulator)
    let reachfive = local
    #else
    let reachfive = remote
    #endif
    #endif

    static func reachfive() -> ReachFive {
        let app = UIApplication.shared.delegate as! AppDelegate
        return app.reachfive
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        print("application:didFinishLaunchingWithOptions:\(launchOptions ?? [:])")

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

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        // Ceci est l'id tel que renvoyé par Apple dans idToken.sub ou AppleIDCredential.user
        appleIDProvider.getCredentialState(forUserID: "000707.3cc381460bce4bcc96e6fd5abdc1f121.1742") { (credentialState, error) in
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
    static func createAlert(title: String, message: String) -> UIAlertController {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: UIAlertController.Style.alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default))
        return alert
    }
}

extension UIViewController {
    func goToProfile(_ authToken: AuthToken) {
        AppDelegate.storage.setToken(authToken)

        Task { @MainActor in
            if let tabBarController = storyboard?.instantiateViewController(withIdentifier: "Tabs") as? UITabBarController {
                tabBarController.selectedIndex = 2 // profile is third from left
                navigationController?.pushViewController(tabBarController, animated: true)
            }
        }
    }

    func showToast(message: String, seconds: Double) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + seconds) {
            alert.dismiss(animated: true)
        }
    }

    func handleLoginFlow(flow: LoginFlow) {
        switch flow {
        case .AchievedLogin(let authToken):
            goToProfile(authToken)
        case .OngoingStepUp(let token, let availableMfaCredentialItemTypes):
            let selectMfaAuthTypeAlert = UIAlertController(title: "Select MFA", message: "Select MFA auth type", preferredStyle: UIAlertController.Style.alert)
            var lastAction: UIAlertAction? = nil
            for type in availableMfaCredentialItemTypes {
                let action = createSelectMfaAuthTypeAction(type: type, stepUpToken: token)
                selectMfaAuthTypeAlert.addAction(action)
                lastAction = action
            }
            selectMfaAuthTypeAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            selectMfaAuthTypeAlert.preferredAction = lastAction
            present(selectMfaAuthTypeAlert, animated: true)
        }
    }

    private func createSelectMfaAuthTypeAction(type: MfaCredentialItemType, stepUpToken: String) -> UIAlertAction {
        return UIAlertAction(title: type.rawValue, style: .default) { _ in
            Task { @MainActor in
                await AppDelegate().reachfive.mfaStart(stepUp: .LoginFlow(authType: type, stepUpToken: stepUpToken)).onSuccess { resp in
                    await self.handleStartVerificationCode(resp, authType: type)
                        .onSuccess { authToken in
                            self.goToProfile(authToken)
                        }
                }
            }
        }
    }

    private func handleStartVerificationCode(_ resp: ContinueStepUp, authType: MfaCredentialItemType) async -> Result<AuthToken, ReachFiveError> {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<AuthToken, ReachFiveError>, Never>) in

            let alert = UIAlertController(title: "Verification code", message: "Please enter the verification code you got by \(authType)", preferredStyle: .alert)
            alert.addTextField { textField in
                textField.placeholder = "Verification code"
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: .failure(.AuthCanceled))
            }
            func submitVerificationCode(withTrustDevice trustDevice: Bool?) -> Void {
                Task { @MainActor in
                    guard let verificationCode = alert.textFields?[0].text, !verificationCode.isEmpty else {
                        print("verification code cannot be empty")
                        continuation.resume(returning: .failure(.AuthFailure(reason: "no verification code")))
                        return
                    }
                    let future = await resp.verify(code: verificationCode, trustDevice: trustDevice)
                        .onFailure { error in
                            let alert = AppDelegate.createAlert(title: "MFA step up failure", message: "Error: \(error.message())")
                            self.present(alert, animated: true)
                        }
                    continuation.resume(returning: future)
                }
            }

            let submitVerificationTrustDevice = UIAlertAction(title: "Trust device", style: .default) { _ in
                submitVerificationCode(withTrustDevice: true)
            }
            let submitVerificationNoTrustDevice = UIAlertAction(title: "Don't trust device", style: .default) { _ in
                submitVerificationCode(withTrustDevice: false)
            }
            let submitVerificationWithoutRba = UIAlertAction(title: "Ignore RBA", style: .default) { _ in
                submitVerificationCode(withTrustDevice: nil)
            }
            alert.addAction(cancelAction)
            alert.addAction(submitVerificationTrustDevice)
            alert.addAction(submitVerificationNoTrustDevice)
            alert.addAction(submitVerificationWithoutRba)
            present(alert, animated: true)
        }
    }
}

extension NSNotification.Name {
    static let DidReceiveLoginCallback = Notification.Name("DidReceiveLoginCallback")
    static let DidReceiveMfaVerifyEmail = Notification.Name("DidReceiveMfaVerifyEmail")
    static let DidReceiveEmailVerificationCallback = Notification.Name("DidReceiveEmailVerificationCallback")
}
