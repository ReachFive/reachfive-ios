# Guide for publication

1. Create a branch with the name of the version `x.x.x`

2. Change the version in `version.rb` file and in `ReachFiveApi`
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

3. Run `./update.sh` to update the dependencies
    ```shell
    ./update.sh
    ```

4. Update the `CHANGELOG.md` file

5. Submit and merge the pull request

6. Add git tag `x.x.x` to the merge commit
    ```sh
    git tag x.x.x
    ```

7. Push the tag
    ```sh
    git push origin x.x.x
    ```

8. The CI will automatically publish this new version

9. Finally, draft a new release in the [Github releases tab](https://github.com/ReachFive/reachfive-ios/releases) (copy & paste the changelog in the release's description).

10. If the new version needs a fork of the documentation, the a `x.x.x` should exist in perpetuity for the purpose of this documentation.<br>
    If, at step 6., the `x.x.x` branch was merged (not squashed) into master, then keep the branch open.<br>
    If the branch was squashed, then delete the branch and recreate a new branch still named `x.x.x`.
