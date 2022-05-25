# Changelog

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
