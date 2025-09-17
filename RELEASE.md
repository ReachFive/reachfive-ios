# Guide for publication

1. Create a branch with the name of the version `x.x.x`

2. Change the version in [version.rb](version.rb) file
    ```ruby
    $VERSION = 'x.x.x'
    ```
3. Run [update.sh](update.sh) to install the new version of this library and update the dependencies in CocoaPods and SPM
    ```shell
    ./update.sh
    ```

4. Update the [CHANGELOG.md](CHANGELOG.md) file
5. Test the modifications on the SPM project DemoSharedCredentials. SPM tends to be stricter than Cocoapods when validating dependencies and code visibility
6. Ask to create a new release version in JIRA and link the ticket to it

7. Submit and merge the pull request

8. Add git tag `x.x.x` to the merge commit
    ```sh
    git tag x.x.x
    ```

9. Push the tag
    ```sh
    git push origin x.x.x
    ```

10. The [CI](https://app.circleci.com/pipelines/github/ReachFive/reachfive-ios) will automatically publish this new version

11. Release Reach5Future

12. Finally, draft a new release in the [Github releases tab](https://github.com/ReachFive/reachfive-ios/releases) (copy & paste the changelog in the release's description)

13. If the new version needs a fork of the documentation, the branch `x.x.x` should exist in perpetuity for the purpose of this documentation.<br>
    If, at step 6., the `x.x.x` branch was merged (not squashed) into master, then keep the branch open.<br>
    If the branch was squashed, then delete the branch and recreate a new branch still named `x.x.x`
