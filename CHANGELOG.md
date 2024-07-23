# Changelog
## v7.0.0
### Breaking changes
- New name for the Pod: `Reach5`

Change all your import from
```
import IdentitySdkCore
```
to
```
import Reach5
```

### New features
- Support for Swift Package Manager
- Support for passkey account recovery

## v6.3.0
### New features
- add MfA credentials support methods:
  - mfaListCredentials, mfaStart, mfaVerify, mfaDeleteCredential
- add MFA step up support methods:
  - mfaStart, mfaVerify
  
### Bug fixes
- Fix a bug where the provided scope parameter was not transmitted to the backend in `webviewLogin`
- Allow the Sandbox app to run in the ARM iPhone simulator 

## v6.2.0
### New features
- Add privacy manifest.

### Bug fix
- Fix a crash when calling `webviewLogin` in quick succession

### Dependencies
- Updated Facebook from 16.2 to 17.0

## v6.1.0
### New features
- Add custom fields in `ProfileAddress` entity.

## v6.0.0

Warning: There are Breaking Changes

### New features
- New module [IdentitySdkWeChat](IdentitySdkWeChat) for native WeChat Login integration 
- Add optional `origin` parameters to most authentification functions to help categorize your inbound traffic

### Bug fix
- Fix passwordless flow with email

### Breaking changes
- The functionality of module `IdentitySdkWebView` has been integrated into the main `IdentitySdkCore` module. Therefore `IdentitySdkWebView` has been deprecated.
- The `origin` parameter in `NativeLoginRequest`, `NewPasskeyRequest`, `PasskeySignupRequest` has changed meaning.
  - Up to now it meant the origin of the webauthn call. There is a new parameter `originWebAuthn` for this
  - Now `origin` has the same meaning as in all other authentification functions: to help categorize your inbound traffic
- Add a new method in `Provider` and `ReachFive`: `application(_:continue:restorationHandler:)` to handle universal links
- Remove an obsolete method in `Provider` and `ReachFive`: `application(_:open:sourceApplication:annotation:)`
- New required property `GIDClientID` in property list to use Google SignIn
- `loadLoginWebview(reachfive:state:nonce:scope:origin:)` now returns a `Future` and instead of taking a `Promise` as argument
- `PasskeySignupRequest` now has its first parameter renamed from `passkeyPofile` to `passkeyProfile`

### Dependencies
- New dependency in Core: DeviceKit
- Updated GoogleSignIn from 6 to 7
- Updated Facebook from 14.1 to 16.2
- Updated Alamofire to 5.8
- Updated CryptoSwift to 1.8

## v5.8.0
### New features

- Support for Passkey in iOS 16 and up:
  - Signup and login are supported in various UI modes
  - Registering a new passkey on an exiting profile (with or without preexisting passkeys)
  - List all passkeys associated to a profile
  - Delete a passkey
- Support for native modal UI to automatically present password credentials

### Demo App
Vastly improved demo app:
- Features a new tab bar navigation UI for easy access to the main demo, profile page and individual functions
- Demo tab that features login and signup using password or passkey
- Profile tab with more profile info, list of passkeys, and buttons to register passkey, change phone number or password
- Access every passkey UI mode individually
- Introducing Mac Catalyst support to easily launch the app outside a simulator on a real Mac device
- Better iPad support
- Support for Dark Mode

### Other changes
- Improved error messages when using the `message()` function or when printing to the console
- Update the Readme with instructions on configuring and running the demo app

## v5.7.2
- Allow login with webview using a WKWebview.
- Add new address complement field in the `ProfileAddress` model

## v5.7.1
- Allow login with password using a custom identifier instead of an email or phone number.
- Update dependency `GoogleSignIn` from 6.2.2 to 6.2.4

## v5.7.0

Warning: There are Breaking Changes

### Breaking changes
- The SDK mandates a minimum version of iOS 13
- `loginWithPassword` takes either an `email` or a `phoneNumber` instead of a `username`
- New method `Provider.application(_:didFinishLaunchingWithOptions:)` to call at startup to initialize the social providers
- New required key `FacebookClientToken` to configure Facebook Login
- Parameter `viewController` in `Provider.login(scope:origin:viewController:)` is now mandatory
- Parameter `viewController` in `Provider.login(scope:origin:viewController:)` must also conform to the protocol `ASWebAuthenticationPresentationContextProviding` when using `WebViewProvider`
- Some error messages may have changed

### New features
- Login using a webview: `AppDelegate.reachfive().webviewLogin`
- `WebViewProvider` now uses `ASWebAuthenticationSession` instead of `SFSafariViewController` for better security. The associated webview UI is different.
- Don't ask again to confirm app access for Facebook Login when a user still has a valid Access Token

### Other changes
- `loginWithPassword` calls `/identity/v1/password/login` instead of `/oauth/token`
- Update dependency `Alamofire` from 5.6.1 to 5.6.2
- Update dependency `BrightFutures` from 8.1.0 to 8.2.0
- Update dependency `CryptoSwift` from 1.3.8 to 1.5.1
- Update dependency `FBSDKCoreKit` from 9.0.0 to 14.1.0
- Update dependency `FBSDKLoginKit` from 9.0.0 to 14.1.0
- Update dependency `GoogleSignIn` from 5.0.2 to 6.2.2
- Remove dependencies `EllipticCurveKeyPair`, `KeychainAccess`, `PromiseKit`, `FacebookCore`, `FacebookLogin`

## v5.6.2
- Remove `WebAuthnKit`

## v5.6.1
- Update `WebAuthnKit` to 0.9.6

## v5.6.0
- Replace deprecated endpoint `/identity/v1/me` by `/identity/v1/userinfo`
- Update `Alamofire` to version 5.6.1
- Update `BrightFutures` to version 8.1.0

## v5.5.1
- Upgrade dependency `GoogleSignIn` to version 5.0.2

## v5.5.0
- Update `FBSDKCoreKit` and `FBSDKLoginKit` to version 9.x
- Add the redirectURL parameter in the signup method
- Upgrade dependencies `CryptoSwift` to version 1.3.2
- Implement keychain access & refresh token on startup

## v5.4.0
- Update `Alamofire` to version 5.x
- Update `Cryptoswift` to latest version

## v5.3.3
- The `sub` claim of an ID token is now correctly deserialized in the
  `id` field of the `OpenIdUser` model
- `ApiError` now has an additional property `errorMessageKey`

## v5.3.2
- Fix `SdkConfig` description in README

## v5.3.1
- Upgrade IdentitySdkCore dependency in IdentitySdkWebview

## v5.3.0
- App-specific scheme handling (pattern `reachfive-${clientId}://callback`). This custom scheme has to be specified in info.plist application and passed during SDK configuration in `SdkConfig` object:
```swift
SdkConfig(
  domain: "my-reachfive-url",
  clientId: "my-reachfive-client-id",
  scheme: "my-reachfive-scheme"
)
```
- This custom scheme will be used as a redirect URL by default in payload of Start Passwordless call.

## v5.2.2
- Fix login with web provider issue (assert() raising a fatal error)
- Fix a PKCE code storage issue

## v5.2.1
- Fix the `isDefault` field in address profiles
- Fix `birthdate`, `bio`, `company`, `external_id`, `locale`, `middle_name`, `nickname`, `picture` and `tos_accepted_at` field in profile

## v5.2.0
- Fix unauthorized errors
- Refactor http errors handling
- Add api errors to `ReachFiveError.AuthFailure` error

### Breaking changes
- `RequestErrors` is renamed to `ApiError`
- `ReachFiveError.AuthFailure` contain an optional parameter of type `ApiError`

## v5.1.2
- Fix get profile without custom fields
- fix http errors handling

## v5.1.1
- Fix http errors handling

## v5.1.0
- Support of refreshToken
- Passwordless code verifification
- Passwordless intercept magic link

### Breaking changes
- The login with provider requires now the `scope` parameter `login(scope: [String]?, origin: String, viewController: UIViewController?).`
- The `signedUid` field was removed from the [Profile](https://developer.reach5.co/api/identity-ios/#profile) model.

## v5.0.0

- Use [Futures](https://github.com/Thomvis/BrightFutures) instead of callbacks, we use the [BrightFutures](https://github.com/Thomvis/BrightFutures) library
- Passwordless Start, it allows to launch the passwordless authentication flow
- Update password

### Breaking changes
We use Future instead callbacks, you need to transform yours callbacks into the Future
```swift
AppDelegate.reachfive()
  .loginWithPassword(username: email, password: password)
  .onSuccess { authToken in
    // Handle success
  }
  .onFailure { error in
    // Handle error
  }
```

instead of

```swift
AppDelegate.reachfive()
  .loginWithPassword(
    username: email,
    password: password,
    callback: { response in
        switch response {
          case .success(let authToken):
            // Handle success
          case .failure(let error):
            // handle error
          }
    }
)
```


## v4.0.0-beta.15
Use SFSafariViewController instead of WKWebView

## v4.0.0-beta.13
Fix UserConsent

## v4.0.0-beta.12
Add getProfile

## v4.0.0

### 9th July 2019

### Changes

New modular version of the Identity SDK iOS:

- [`IdentitySdkCore`](IdentitySdkCore)
- [`IdentitySdkFacebook`](IdentitySdkFacebook)
- [`IdentitySdkGoogle`](IdentitySdkGoogle)
- [`IdentitySdkWebView`](IdentitySdkWebView)
