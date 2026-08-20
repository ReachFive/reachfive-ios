import XCTest
@testable import Reach5

/// What the `/identity/v1/providers` payload may carry in `universal_link` without costing the configuration.
///
/// The regression guarded against: an unusable value used to be a *decoding* failure, and a `Decodable` array
/// is all-or-nothing, so it aborted the whole payload — `initialize()` failed permanently and every provider
/// was lost, not only the one whose link was wrong.
final class ProviderConfigTests: XCTestCase {

    /// The very decoder `ReachFiveApi.init` hands to the network client.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Google first, so a test tells "this one link is ignored" from "the payload is lost".
    private func bconnect(universalLink: String) throws -> ProviderConfig {
        let json = Data("""
        {"status": "ok", "items": [
          {"provider": "google", "variant": "", "client_id": "google-client", "scope": ["openid"]},
          {"provider": "bconnect", "variant": "", "client_id": "bconnect-client", "universal_link": \(universalLink), "scope": ["openid"]}
        ]}
        """.utf8)
        let result = try decoder.decode(ProvidersConfigsResult.self, from: json)
        XCTAssertEqual(result.items.count, 2, "every provider of the payload must survive")
        return result.items[1]
    }

    // MARK: - Links a universal-link session can use

    func testAnAbsoluteHttpsLinkIsKept() throws {
        let config = try bconnect(universalLink: #""https://example.com/callback""#)
        XCTAssertEqual(config.universalLink?.absoluteString, "https://example.com/callback")
    }

    func testAHostWithoutAPathIsKept() throws {
        let config = try bconnect(universalLink: #""https://example.com""#)
        XCTAssertEqual(config.universalLink?.absoluteString, "https://example.com")
    }

    /// The host check folds the case (RFC 3986 §3.2.2), but the value itself is kept verbatim: it is the
    /// `redirect_uri` the console whitelisted, and the backend compares it byte for byte.
    func testTheCheckFoldsTheCaseButKeepsTheValueVerbatim() throws {
        let config = try bconnect(universalLink: #""https://Example.COM/CallBack""#)
        XCTAssertEqual(config.universalLink?.absoluteString, "https://Example.COM/CallBack")
    }

    // MARK: - Links it cannot, none of which may cost the payload

    /// The regression itself: `URL(string: "")` is nil, and `""` is what an unset text field in the console
    /// yields.
    func testAnEmptyLinkIsIgnoredWithoutLosingTheOtherProviders() throws {
        XCTAssertNil(try bconnect(universalLink: #""""#).universalLink)
    }

    /// `URL(string:)` accepts these as relative references, so they used to decode into a `URL` with no host
    /// and only failed much later, when the session was built.
    func testALinkWithoutAHostIsIgnored() throws {
        for raw in [#""toto""#, #""toto ""#, #""example.com/callback""#, #""/callback""#] {
            XCTAssertNil(try bconnect(universalLink: raw).universalLink, "\(raw) has no host")
        }
    }

    func testAnAbsentLinkAndAnExplicitNullAreEquivalent() throws {
        XCTAssertNil(try bconnect(universalLink: "null").universalLink)

        let withoutTheField = Data(#"{"status":"ok","items":[{"provider":"bconnect","variant":"","client_id":"c","scope":["openid"]}]}"#.utf8)
        let result = try decoder.decode(ProvidersConfigsResult.self, from: withoutTheField)
        XCTAssertNil(result.items[0].universalLink)
    }

    // MARK: - The other fields still decode as before

    func testTheOtherFieldsDecodeAsBefore() throws {
        let config = try bconnect(universalLink: #""https://example.com/callback""#)
        XCTAssertEqual(config.provider, "bconnect")
        XCTAssertEqual(config.variant, "")
        XCTAssertEqual(config.clientId, "bconnect-client")
        XCTAssertEqual(config.scope, ["openid"])
        XCTAssertEqual(config.providerWithVariant, "bconnect:")
    }

    func testAnOptionalFieldIsNilWhenAbsent() throws {
        let bare = Data(#"{"status":"ok","items":[{"provider":"p","variant":"v"}]}"#.utf8)
        let config = try decoder.decode(ProvidersConfigsResult.self, from: bare).items[0]
        XCTAssertNil(config.clientId)
        XCTAssertNil(config.scope)
    }

    func testAMissingRequiredFieldStillFails() {
        let withoutProvider = Data(#"{"status":"ok","items":[{"variant":"","client_id":"c"}]}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ProvidersConfigsResult.self, from: withoutProvider))
    }
}
