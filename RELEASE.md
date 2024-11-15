# Guide for publication

1. Create a branch with the name of the version `x.x.x`

2. Change the version in [version.rb](version.rb) file and in [ReachFiveApi.swift](Sources/Core/Classes/ReachFiveApi.swift)
    ```ruby
    $VERSION = 'x.x.x'
    ```
    ```swift
    let defaultParams: [String: String] = [
        "platform": "ios",
        // TODO: read from the version.rb. Either directly or indirectly from Reach5.h, Info.plist...
        "sdk": "x.x.x",
        "device": deviceInfo,
    ]
    ```

3. Run [update.sh](update.sh) to install the new version of this library and update the dependencies
    ```shell
    ./update.sh
    ```

4. Update to latest package versions for SPM in XCode or with this command
    ```shell
    swift package update
    ```

5. Update the [CHANGELOG.md](CHANGELOG.md) file
6. Test the modifications on the SPM project DemoSharedCredentials. SPM tends to be stricter than Cocoapods when validating dependencies and code visibility.

7. Submit and merge the pull request

8. Add git tag `x.x.x` to the merge commit
    ```sh
    git tag x.x.x
    ```

9. Push the tag
    ```sh
    git push origin x.x.x
    ```

10. The CI will automatically publish this new version

11. Finally, draft a new release in the [Github releases tab](https://github.com/ReachFive/reachfive-ios/releases) (copy & paste the changelog in the release's description).

12. If the new version needs a fork of the documentation, the branch `x.x.x` should exist in perpetuity for the purpose of this documentation.<br>
    If, at step 7., the `x.x.x` branch was merged (not squashed) into master, then keep the branch open.<br>
    If the branch was squashed, then delete the branch and recreate a new branch still named `x.x.x`.
