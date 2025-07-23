import Reach5

let scope = ["openid", "email", "profile", "phone", "full_write", "offline_access"]

Task {
    do {
        let response = try await AppDelegate.reachfive().mfaStart(
            stepUp: .LoginFlow(
                authType: "email",
                stepUpToken: "stepUpToken123",
                redirectUri: "https://example.com/callback",
                origin: "ios-app"
            )
        )
        // Do something
    } catch {
        // Return a ReachFive error
    }
}
