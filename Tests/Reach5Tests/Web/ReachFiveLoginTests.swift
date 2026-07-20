import XCTest
@testable import Reach5

/// `buildAuthorizeURL`, focus sur `loginUrlFragment` : encodage du fragment de l'URL `/oauth/authorize`
/// pour la personnalisation de la Login URL dans un flow de token orchestration.
@MainActor
final class ReachFiveLoginTests: XCTestCase {
    private let reachFive = ReachFive(sdkConfig: SdkConfig(domain: "example.reach5.net", clientId: "abc"))

    private func buildURL(loginUrlFragment: [String: String]? = nil) -> URL {
        let u = reachFive.buildAuthorizeURL(pkce: Pkce.generate(), loginUrlFragment: loginUrlFragment)
        print(u.absoluteString)
        return u
    }

    /// Décode le fragment (déjà percent-encodé) comme une query string, pour comparer les paires
    /// sans dépendre de leur ordre (non garanti par `[String: String]`).
    private func fragmentPairs(of url: URL) -> [String: String] {
        guard let encodedFragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment else {
            return [:]
        }
        let components = URLComponents(string: "?" + encodedFragment)
        return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    /// Raw (percent-encoded) fragment string, as it would actually appear in the URL — as opposed to
    /// `fragmentPairs`, which decodes it back. Use this to check what does or doesn't get escaped.
    private func rawFragment(of url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment ?? ""
    }

    // MARK: - Presence of the fragment

    func testNoFragmentWhenLoginUrlFragmentIsNil() {
        XCTAssertNil(buildURL(loginUrlFragment: nil).fragment)
    }

    func testNoFragmentWhenLoginUrlFragmentIsEmpty() {
        XCTAssertNil(buildURL(loginUrlFragment: [:]).fragment)
    }

    func testFragmentContainsProvidedPairs() {
        let url = buildURL(loginUrlFragment: ["site": "gourmet", "campaign": "spring"])
        XCTAssertEqual(fragmentPairs(of: url), ["site": "gourmet", "campaign": "spring"])
    }

    func testFragmentContainsURL() {
        let complicatedUrl = "https://example.reach5.net/oauth/authorize?redirect_uri=reachfive-abc://callback&sdk=unknown&code_challenge_method=S256&code_challenge=pnd5ZOTn62fsNUatYPPqayE15wlZq29gFs1UDp1PalM&client_id=abc&scope=&response_type=code&platform=ios#treats=%F0%9F%A5%90%E2%98%95%EF%B8%8F%F0%9F%8E%89&site=Gourmet%20%26%20L'%C3%89tudiant%20%231%20/%20100%25%20d%C3%A9jant%C3%A9?&secret=%F0%9B%85%B0%F0%9B%85%B1%F0%9B%85%B2%F0%9B%85%B3%F0%9B%85%B4&empty=&math=a%3Db+c&LoginURLParameter=1234"
        let url = buildURL(loginUrlFragment: ["site": complicatedUrl])
        XCTAssertEqual(fragmentPairs(of: url), ["site": complicatedUrl])
    }

    func testFragmentDoesNotAffectQueryParams() {
        let url = buildURL(loginUrlFragment: ["site": "gourmet"])
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        XCTAssertTrue(query.contains { $0.name == "client_id" && $0.value == "abc" })
    }

    // MARK: - Value encoding

    /// Whatever a client puts in a value must come out on the other end exactly as given: the Login
    /// URL's JS reads it back via `window.location.hash`, so this is the actual contract we're testing.
    func testValuesRoundTripThroughTheFragment() {
        let values = [
            "1234", // baseline: plain alphanumeric, no encoding needed
            "gourmet", // baseline: plain alphanumeric, no encoding needed
            "a b", // whitespace must be percent-encoded
            "a%b", // '%' must be percent-encoded
            "a:b", // ':' is allowed as-is in a fragment
            "a/b", // '/' is allowed as-is in a fragment
            "a?b", // '?' is allowed as-is in a fragment
            "Été", // accented letters must be percent-encoded as UTF-8
            "日本語", // non-Latin script must be percent-encoded as UTF-8
            "🎉", // emoji must be percent-encoded as UTF-8
            "", // an empty value is preserved, not dropped
        ]
        for value in values {
            let url = buildURL(loginUrlFragment: ["v": value])
            XCTAssertEqual(fragmentPairs(of: url)["v"], value, "value \(value.debugDescription) should round-trip unchanged")
        }
    }

    /// These characters are structural to the fragment/query grammar itself (pair separator, key/value
    /// separator, fragment-truncating `#`): a naive `"\(key)=\(value)"` join — the previous
    /// implementation — would let them corrupt the fragment's structure instead of just being part of
    /// a value. Checked against the *raw* fragment, not the round-trip, since round-tripping through our
    /// own decoder can't detect a value that was never escaped in the first place.
    func testStructuralCharactersAreEscapedInValues() {
        let values = [
            "x&y", // '&' is the pair separator
            "a=b", // '=' is the key/value separator
            "a#b", // '#' would otherwise start a *second* fragment
        ]
        for value in values {
            let url = buildURL(loginUrlFragment: ["v": value])
            XCTAssertFalse(rawFragment(of: url).contains(value), "\(value.debugDescription) should be percent-encoded, not appear raw")
            XCTAssertEqual(fragmentPairs(of: url)["v"], value)
        }
    }

    /// Unlike the characters above, `+` is not part of the fragment/query grammar, so `URLComponents`
    /// leaves it unescaped. This is a known caveat, not a bug: a Login URL that parses
    /// `window.location.hash` with `URLSearchParams` (which follows the `application/x-www-form-urlencoded`
    /// convention) will read a literal `+` back as a space. Values are expected to avoid `+` in practice.
    func testPlusSignIsNotEscaped() {
        let url = buildURL(loginUrlFragment: ["v": "a+b"])
        XCTAssertEqual(rawFragment(of: url), "v=a+b")
    }

    func testMultiplePairsAreEachPreservedIndependently() {
        let url = buildURL(loginUrlFragment: ["a": "x&y", "b": "z z"])
        XCTAssertEqual(fragmentPairs(of: url), ["a": "x&y", "b": "z z"])
    }
}
