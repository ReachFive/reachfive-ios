# Guide for publication

1. Create a branch with the name of the version `x.x.x`

2. Change the version in [version.rb](version.rb) file
    ```ruby
    $VERSION = 'x.x.x'
    ```
3. Run [set_version.sh](set_version.sh) to regenerate [SdkVersion.swift](Sources/Core/Classes/SdkVersion.swift) from `version.rb`.
   Make sure the resulting change is committed, the CI checks that it stays in sync.
    ```shell
    ./set_version.sh
    ```

4. Update the [CHANGELOG.md](CHANGELOG.md) file (don't forget to move the unreleased changes to their own section)
5. Ask to create a new release version in JIRA and link the ticket to it

6. Submit and merge the pull request

7. Add git tag `11.0.0` to the merge commit
    ```sh
    git tag 11.0.0
    ```

8. Push the tag
    ```sh
    git push origin 11.0.0
    ```

9. The tag is the published version: SPM resolves it directly, there is nothing else to publish

10. Release Reach5Future

11. If this is a major version, release Reach5Google and Reach5Facebook with updated Package.swift .upToNextMajor(from:) declaration

12. Bump the pinned versions in the SPM project DemoSharedCredentials to the new tags (Reach5 and, if released, Reach5Future) and test it. This is the first point where the actually-published versions can be resolved and built together.

13. Finally, draft a new release in the [Github releases tab](https://github.com/ReachFive/reachfive-ios/releases) (copy & paste the changelog in the release's description)

14. If the new version needs a fork of the documentation, the branch `x.x.x` should exist in perpetuity for the purpose of this documentation.<br>
    If, at step 6., the `x.x.x` branch was merged (not squashed) into master, then keep the branch open.<br>
    If the branch was squashed, then delete the branch and recreate a new branch still named `x.x.x`
