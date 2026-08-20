import XCTest
@testable import Reach5

/// Documents what the `/identity/v1/providers` payload may carry in `universal_link` without costing the
/// whole configuration. The regression guarded against: a single unusable value used to abort the decoding of
/// the entire payload, so `initialize()` failed for good and *every* provider was lost — not only the one
/// whose link was wrong.
final class ProviderConfigTests: XCTestCase {

    /// The very decoder `ReachFiveApi.init` hands to the network client.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Two providers, so a test can tell "this one link is ignored" from "the payload is lost".
    private func payload(universalLink: String) -> Data {
        Data("""
        {
          "status": "ok",
          "items": [
            {"provider": "google", "variant": "", "client_id": "google-client", "scope": ["openid"]},
            {"provider": "bconnect", "variant": "", "client_id": "bconnect-client", "universal_link": \(universalLink), "scope": ["openid"]}
          ]
        }
        """.utf8)
    }

    private func bconnect(universalLink: String) throws -> ProviderConfig {
        let result = try decoder.decode(ProvidersConfigsResult.self, from: payload(universalLink: universalLink))
        XCTAssertEqual(result.items.count, 2, "every provider of the payload must survive")
        return result.items[1]
    }

    // MARK: - Values a universal-link session can use

    func testAnAbsoluteHttpsLinkIsKept() throws {
        let config = try bconnect(universalLink: #""https://example.com/callback""#)
        XCTAssertEqual(config.universalLink?.absoluteString, "https://example.com/callback")
    }

    func testAHostWithoutAPathIsKept() throws {
        let config = try bconnect(universalLink: #""https://example.com""#)
        XCTAssertEqual(config.universalLink?.absoluteString, "https://example.com")
    }

    // MARK: - Values it cannot, none of which may cost the payload

    /// The regression itself: `URL(string: "")` is nil, so decoding straight into a `URL` threw
    /// `dataCorrupted` and took Google's configuration down with b.connect's.
    func testAnEmptyLinkIsIgnoredWithoutLosingTheOtherProviders() throws {
        let config = try bconnect(universalLink: #""""#)
        XCTAssertNil(config.universalLink)
    }

    /// `URL(string:)` accepts these as relative references, so they used to decode into a `URL` with no
    /// scheme and no host, and only failed much later — when the session was built, under a message blaming
    /// the iOS version first.
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

    func testTheOtherFieldsAreUnaffectedByTheHandWrittenDecoder() throws {
        let config = try bconnect(universalLink: #""https://example.com/callback""#)
        XCTAssertEqual(config.provider, "bconnect")
        XCTAssertEqual(config.variant, "")
        XCTAssertEqual(config.clientId, "bconnect-client")
        XCTAssertEqual(config.scope, ["openid"])
        XCTAssertEqual(config.providerWithVariant, "bconnect:")
    }

    func testAMissingRequiredFieldStillFails() {
        let withoutProvider = Data(#"{"status":"ok","items":[{"variant":"","client_id":"c"}]}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(ProvidersConfigsResult.self, from: withoutProvider))
    }
}
