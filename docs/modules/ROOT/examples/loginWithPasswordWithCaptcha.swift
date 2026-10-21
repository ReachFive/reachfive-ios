// A captcha token is single-use and expires after about two minutes: obtain it right before the
// call that needs it, never ahead of time.
let captchaToken: String = // Here paste the token your captcha provider just returned

do {
    let authToken = try await AppDelegate.reachfive().loginWithPassword(
        email: "john.doe@gmail.com",
        password: "UCrcF4RH",
        captcha: Captcha(token: captchaToken, provider: .reCaptcha)
    )
    // Get the profile's authentication token
} catch {
    // A refused captcha is not told apart from any other access denial: the reason is in the
    // ReachFive server logs, not in this error.
}
