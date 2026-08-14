import Reach5Macros
import SwiftSyntaxMacrosTestSupport
import XCTest

/// What `#WebAuthnOrigin` accepts, what it refuses, and what it says when it refuses.
///
/// The accepted/refused rows deliberately mirror `SdkConfigTests`' origin cases: the two suites must agree,
/// since they exercise the same `WebAuthnOrigin.rejection(of:)` from either side of the compile/run boundary.
/// A row that starts to disagree is the drift this whole shared target exists to make impossible.
final class WebAuthnOriginMacroTests: XCTestCase {
    private let macros = ["WebAuthnOrigin": WebAuthnOriginMacro.self]

    func testAcceptsASerializedOrigin() {
        assertMacroExpansion(
            #"#WebAuthnOrigin("https://auth.example.com")"#,
            expandedSource: #"URL(string: "https://auth.example.com")!"#,
            macros: macros)
    }

    func testAcceptsANonDefaultPort() {
        assertMacroExpansion(
            #"#WebAuthnOrigin("https://auth.example.com:8443")"#,
            expandedSource: #"URL(string: "https://auth.example.com:8443")!"#,
            macros: macros)
    }

    /// Punycode is the A-label form RFC 6454 §6.2 wants, and the form `createUrl` sends: an integrator who
    /// writes the Unicode spelling gets the ASCII one suggested rather than a mismatch at the server.
    func testRefusesANonASCIIHostAndSuggestsItsALabel() {
        assertMacroExpansion(
            #"#WebAuthnOrigin("https://café.example")"#,
            expandedSource: #"URL(string: "")!"#,
            diagnostics: [
                DiagnosticSpec(
                    message: "a WebAuthn origin is a scheme, a host and a non-default port only — write 'https://xn--caf-dma.example'",
                    line: 1,
                    column: 17,
                    fixIts: [FixItSpec(message: "Replace with 'https://xn--caf-dma.example'")]),
            ],
            macros: macros)
    }

    func testRefusesATrailingSlash() {
        assertMacroExpansion(
            #"#WebAuthnOrigin("https://auth.example.com/")"#,
            expandedSource: #"URL(string: "")!"#,
            diagnostics: [
                DiagnosticSpec(
                    message: "a WebAuthn origin is a scheme, a host and a non-default port only — write 'https://auth.example.com'",
                    line: 1,
                    column: 17,
                    fixIts: [FixItSpec(message: "Replace with 'https://auth.example.com'")]),
            ],
            macros: macros)
    }

    func testRefusesAPath() {
        assertMacroExpansion(
            #"#WebAuthnOrigin("https://auth.example.com/webauthn")"#,
            expandedSource: #"URL(string: "")!"#,
            diagnostics: [
                DiagnosticSpec(
                    message: "a WebAuthn origin is a scheme, a host and a non-default port only — write 'https://auth.example.com'",
                    line: 1,
                    column: 17,
                    fixIts: [FixItSpec(message: "Replace with 'https://auth.example.com'")]),
            ],
            macros: macros)
    }

    /// `:443` is the scheme's default, so RFC 6454 §6.2.5 omits it — and the SDK would too, leaving the
    /// integrator's literal and the sent origin different.
    func testRefusesADefaultPort() {
        assertMacroExpansion(
            #"#WebAuthnOrigin("https://auth.example.com:443")"#,
            expandedSource: #"URL(string: "")!"#,
            diagnostics: [
                DiagnosticSpec(
                    message: "a WebAuthn origin is a scheme, a host and a non-default port only — write 'https://auth.example.com'",
                    line: 1,
                    column: 17,
                    fixIts: [FixItSpec(message: "Replace with 'https://auth.example.com'")]),
            ],
            macros: macros)
    }

    /// The host-less authority that costs `SdkConfig` a runtime check: `URL.host` is `""`, not `nil`.
    func testRefusesAHostLessAuthority() {
        assertMacroExpansion(
            #"#WebAuthnOrigin("https://:8443")"#,
            expandedSource: #"URL(string: "")!"#,
            diagnostics: [
                DiagnosticSpec(
                    message: "a WebAuthn origin needs a scheme and a host, e.g. https://auth.example.com",
                    line: 1,
                    column: 17),
            ],
            macros: macros)
    }

    func testRefusesABareHost() {
        assertMacroExpansion(
            #"#WebAuthnOrigin("auth.example.com")"#,
            expandedSource: #"URL(string: "")!"#,
            diagnostics: [
                DiagnosticSpec(
                    message: "a WebAuthn origin needs a scheme and a host, e.g. https://auth.example.com",
                    line: 1,
                    column: 17),
            ],
            macros: macros)
    }

    /// The defensive branch. In a real build an interpolated literal never reaches the plugin — `StaticString`
    /// rejects it with the type checker's own error ("cannot convert value of type 'String'…"), verified by
    /// compiling one. `assertMacroExpansion` does not type-check, which is what lets this branch be tested at
    /// all; it exists so that syntax the type checker does let through still gets a message naming the runtime
    /// alternative instead of a crash in the plugin.
    func testRefusesAnInterpolatedLiteral() {
        assertMacroExpansion(
            ##"""
            let host = "auth.example.com"
            #WebAuthnOrigin("https://\(host)")
            """##,
            expandedSource: ##"""
            let host = "auth.example.com"
            URL(string: "")!
            """##,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        '#WebAuthnOrigin' needs a string literal written here, with no interpolation. \
                        For an origin known only at runtime, pass it to 'SdkConfig(originWebAuthn:)' as a URL: \
                        it is validated there too.
                        """,
                    line: 2,
                    column: 1),
            ],
            macros: macros)
    }
}
