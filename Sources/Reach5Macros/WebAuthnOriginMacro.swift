import Reach5URLValidation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Expands `#WebAuthnOrigin("https://auth.example.com")` into `URL(string: "https://auth.example.com")!`,
/// having checked the literal with `WebAuthnOrigin.rejection(of:)` — the same function `SdkConfig` runs at init.
///
/// The force-unwrap in the expansion is not a bet: it is reached only when `URL(string:)` already returned a
/// value for this exact literal inside the plugin. What the plugin cannot guarantee is that it parsed with the
/// same Foundation the device will use, so a disagreement between build machine and runtime surfaces here as a
/// false compile error on an exotic origin — never as a crash.
public struct WebAuthnOriginMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let argument = node.arguments.first?.expression,
              let literal = argument.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              case let .stringSegment(segment)? = literal.segments.first
        else {
            // Defensive: `StaticString` in the macro's declaration already rejects both a runtime `String`
            // and an interpolated literal, with the type checker's own error, before the plugin ever runs.
            // This branch only covers syntax the type checker would let through, so its wording points at the
            // runtime alternative rather than describing the input.
            context.diagnose(
                Diagnostic(
                    node: node,
                    message: Message.notALiteral,
                    // Nothing to suggest: an origin known only at runtime belongs to `SdkConfig`'s runtime
                    // check, not to a macro. Naming that alternative is the useful part of the error.
                    highlights: [Syntax(node)]))
            return "URL(string: \"\")!"
        }

        let text = segment.content.text
        guard let rejection = WebAuthnOrigin.rejection(of: text) else {
            return "URL(string: \(literal))!"
        }

        context.diagnose(
            Diagnostic(
                node: Syntax(literal),
                message: Message.rejected(rejection),
                fixIts: rejection.correction.map { correction in
                    [FixIt(
                        message: Message.replace(with: correction),
                        changes: [.replace(
                            oldNode: Syntax(literal),
                            newNode: Syntax(StringLiteralExprSyntax(content: correction)))])]
                } ?? []))

        // Emitting a well-formed expression alongside the error keeps the failure to one diagnostic: returning
        // nothing would make every use of the result report "cannot find value" on top of it.
        return "URL(string: \"\")!"
    }

    enum Message: DiagnosticMessage, FixItMessage {
        case notALiteral
        case rejected(WebAuthnOrigin.Rejection)
        case replace(with: String)

        var message: String {
            switch self {
            case .notALiteral:
                return """
                    '#WebAuthnOrigin' needs a string literal written here, with no interpolation. \
                    For an origin known only at runtime, pass it to 'SdkConfig(originWebAuthn:)' as a URL: \
                    it is validated there too.
                    """
            case let .rejected(rejection):
                return rejection.message
            case let .replace(correction):
                return "Replace with '\(correction)'"
            }
        }

        var severity: DiagnosticSeverity { .error }

        var diagnosticID: MessageID {
            MessageID(domain: "Reach5Macros", id: "WebAuthnOrigin")
        }

        var fixItID: MessageID { diagnosticID }
    }
}

@main
struct Reach5MacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [WebAuthnOriginMacro.self]
}
