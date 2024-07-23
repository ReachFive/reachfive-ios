# Running the Demo Application

Install [Cocoapods](https://cocoapods.org).

```sh
sudo gem install cocoapods

cd Sandbox
pod install

open Sandbox.xcworkspace

pod update
```

### Configure the Sandbox

#### Configure your account

On https://developer.apple.com/account, create an Identifier for an App ID.
Choose a `bundle ID`.<br>
To use the full extent of the Sandbox app features, select the `Associated Domains` and `Sign In with Apple` capabilities.

On XCode, connect your account.

In the navigator area, select `Sandbox` at the root, then in the editor area, in `Targets` select `Sandbox` (which should be selected by default) then "Signing & Capabilities".<br>
Fill in your `bundle ID`.
Add the `Associated Domains` and `Sign In with Apple` capabilities. <br>
Configure the associated domains as explained below.

##### Configure the associated domains
In Domains, enter `webcredentials:domain`. <br>
The domain must be the same as in the `SdkConfig`, so for example `webcredentials:integ-sandbox-squad2.reach5.dev`.<br>
If you use a private web server, which is unreachable from the public internet, you can also enable the alternate mode feature by appending `?mode=<alternate mode>`.<br>
So for example `webcredentials:integ-sandbox-squad2.reach5.dev?mode=developer`

cf. https://developer.apple.com/documentation/xcode/supporting-associated-domains

#### Connect to your backend
You also need to set the ReachFive client configuration within the SDK as below:

```
SdkConfig(
  domain: "my-reachfive-url",
  clientId: "my-reachfive-client-id"
)
```


For example:
```
SdkConfig(
    domain: "integ-sandbox.reach5.dev",
    clientId: "zhU43aRKZtzps551nvOM"
)
```

By default, the URL scheme follows this pattern: `reachfive-${clientId}://callback`.
You can also specify it manually.

#### Configure your backend

The client that you just referenced must be a `First-party client` with `Token Endpoint Authentication Method` at `None`.<br>
You must have the scheme registered in `Allowed Callback URLs`.<br>
You should also enforce PKCE and enable Refresh Tokens.<br>
If you want to use Passkeys, you must have the `Webauthn` feature activated on your account, and add your domain in `Allowed Origins` like this: `https://integ-sandbox-squad2.reach5.dev`.<br>
Note the `https://` here that was not present in the `SdkConfig`.

#### Run Sandbox on a real device
To run your app on a device and not just the simulator (to use Passkeys for example), you need to enable "Developer Mode".<br>
On iPhone, iPad, go to Settings > Privacy & Security > Developer Mode.<br>
On a Mac, run in your terminal:
```shell
swcutil developer-mode -e true
```

# Development

## Viewing the modules as libraries in XCode

Open the project folder to view it as a package project, not the .xcodeproj or .xcworkspace which makes them seen as a Pod project


## Adding or renaming files
While you can develop across all modules while being in the `Sandbox.xcworkspace`, 
when you need to add a new file or rename one, you have to be in the specific module workspace and add it from within XCode so that the `project.pbxproj` is properly updated.

## Modules
A podspec cannot reference, without resorting to dirty tricks, other locally changed pods.<br>
Instead they reference the latest version available on Cocoapods.<br>
This means that the non-core pods will not have access to the core changes on CI until the core changes are deployed.<br>
Local development is not impacted by this problem.

So first release IdentitySdkCore, then you can use the new APIs from this release in the Facebook/Google/Webview/WeChat pods.

### When to add a new module for a provider

If the provider depends on an external dependency or needs a specific configuration in the property file, then add a new module, otherwise add it to Core.

For example a native Apple Provider should not be in a new module.<br>
Also a provider that would depend only on specific web configuration not possible to do in `WebViewProvider`.<br>
Or one that would use `SFSafariViewController` instead of `ASWebAuthenticationSession` (not sure that it is a good idea, it is just an example).

### How to add a new module (e.g. for a new provider)
XCode > File > New > Project... > Framework.

Create the Podfile and podspec (with pod commands or by copying from other modules).

Be aware, as per point above, that the podspec does not reference the local version but the remote version.

Add at least one file for now, push and tag (why 5.9.0-beta worked and not 5.9.0 might forever remain a mystery).<br/>
Push the new pod `pod trunk push` so that XCode can show the proper icon in the Products view

