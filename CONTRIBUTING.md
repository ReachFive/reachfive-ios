# Running the Demo Application

Check out `reachfive-ios-google` and `reachfive-ios-facebook` next to this repository, then open `Sandbox/Sandbox.xcodeproj` in Xcode: Reach5, Reach5Google and Reach5Facebook are resolved automatically as local Swift packages (`../`, `../../reachfive-ios-google`, `../../reachfive-ios-facebook`).

The directory holding this repository has to be named `reachfive-ios`. SwiftPM derives the identity of a local package from its directory name, so under any other name (a git worktree, for instance) it sees two distinct packages both defining `Reach5` and refuses to resolve the graph:
```
multiple similar targets 'Reach5' appear in package 'reachfive-ios' and '<the other name>'
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

## Linting & formatting

The project uses [SwiftLint](https://github.com/realm/SwiftLint) (linter) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (formatter), configured via `.swiftlint.yml` and `.swiftformat` at the repo root.

```sh
brew install swiftlint swiftformat
```

- **SwiftLint** runs automatically as a build phase in both `Reach5.xcodeproj` and `Sandbox.xcodeproj`; violations show up as warnings/errors directly in Xcode.
- **SwiftFormat** runs on staged files via a git hook before each commit. Enable it once per clone with:
  ```sh
  git config core.hooksPath .githooks
  ```

You can also run either tool manually on the whole repo:
```sh
swiftlint lint
swiftformat .
```

## Running the tests

`Reach5Tests` belongs to the root package, and Xcode only exposes the test targets of the package it has open as the root — not those of a package consumed as a dependency. So the tests are invisible from the Sandbox project: open the repository folder itself in Xcode to get them.

From the command line, Mac Catalyst is the quickest destination, as it runs UIKit on macOS without booting a simulator:
```sh
xcodebuild -scheme Reach5 -destination 'platform=macOS,variant=Mac Catalyst' test
```
CI runs the same suite on a simulator, because that is the destination our users build for:
```sh
xcodebuild -scheme Reach5 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

## Viewing the modules as libraries in XCode

Open the project folder to view it as a package project, not the .xcodeproj.

## Adding or renaming files
The module sources are declared by `Package.swift`, which picks them up from the directory, so adding or renaming a file there needs no project bookkeeping.<br>
The Sandbox is a regular Xcode project: add or rename its files from within XCode so that `Sandbox.xcodeproj/project.pbxproj` is properly updated.

## Modules
Reach5Google and Reach5Facebook declare Reach5 as a *remote* dependency, on the published GitHub tags, so that their own CI can build them on their own.

The Sandbox is what makes local Core changes visible to them: it declares all three as local Swift packages, and a local package in the root manifest takes precedence over a remote dependency of the same identity. So the modules opened *through the Sandbox* compile against your working copy of Core, with no release needed. SwiftPM reports the override as a warning, which is expected:
```
Conflicting identity for reachfive-ios: dependency 'github.com/reachfive/reachfive-ios' and
dependency '<local path>' both point to the same package identity 'reachfive-ios'.
```

Opened on its own, outside the Sandbox, a module resolves Reach5 from GitHub and your local Core changes are silently ignored. The same goes for each module's CI: it builds against whatever Reach5 version its `Package.swift` declares, so a Core change only reaches it once a new Reach5 version is released.

### When to add a new module for a provider

If the provider depends on an external dependency or needs a specific configuration in the property file, then add a new module, otherwise add it to Core.

For example, a native Apple Provider should not be in a new module.<br>
Also a provider that would depend only on specific web configuration not possible to do in `WebViewProvider`.<br>
Or one that would use `SFSafariViewController` instead of `ASWebAuthenticationSession` (not sure that it is a good idea, it is just an example).

### How to add a new module (e.g. for a new provider)
XCode > File > New > Project... > Framework.

Create the `Package.swift` (by copying from other modules).

Add at least one file for now, push and tag.

