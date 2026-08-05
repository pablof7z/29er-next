import Foundation
import SwiftParser
import SwiftSyntax
final class BoundaryVisitor: SyntaxVisitor {
    private let policy: BoundaryPolicy
    private let path: String
    private let converter: SourceLocationConverter
    private let source: String
    private let rowStorageNames: Set<String>
    private var symbolStack: [String] = []
    private var rowContextStack: [Bool] = []
    private var seen: Set<String> = []
    var violations: [BoundaryViolation] = []
    var matchedExceptionCounts: [String: Int] = [:]

    init(
        policy: BoundaryPolicy,
        path: String,
        tree: SourceFileSyntax,
        source: String,
        rowStorageNames: Set<String>
    ) {
        self.policy = policy
        self.path = path
        converter = SourceLocationConverter(fileName: path, tree: tree)
        self.source = source
        self.rowStorageNames = rowStorageNames
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        match(.importName, value: node.path.trimmedDescription, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        match(.identifier, value: node.baseName.text, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        match(.identifier, value: node.name.text, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let base = node.base?.trimmedDescription
        match(
            .memberAccess,
            value: node.declName.baseName.text,
            base: base,
            node: Syntax(node),
            rowContext: isRowContext || isRowStorageBase(base)
        )
        if node.declName.baseName.text == "unsigned",
           base == nil || base?.contains("Write") == true {
            match(.unsignedPayload, value: "payload.unsigned", node: Syntax(node))
        }
        return .visitChildren
    }

    override func visit(_ node: KeyPathExprSyntax) -> SyntaxVisitorContinueKind {
        let value = node.trimmedDescription.dropFirst(2)
        match(
            .memberAccess,
            value: String(value),
            node: Syntax(node),
            rowContext: isRowContext || !rowStorageNames.isEmpty
        )
        return .visitChildren
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        guard let value = node.representedLiteralValue else { return .visitChildren }
        match(.stringContains, value: value, node: Syntax(node), contains: true)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        for argument in node.arguments {
            guard let label = argument.label?.text,
                  let literal = argument.expression.as(IntegerLiteralExprSyntax.self) else {
                continue
            }
            match(
                .integerArgument,
                value: literal.literal.text.replacingOccurrences(of: "_", with: ""),
                argumentLabel: label,
                node: Syntax(literal)
            )
        }
        let secretTokens = ["secretKey", "secret_key", "privateKey", "private_key", "nsec"]
        if secretTokens.contains(where: node.trimmedDescription.contains) {
            let callee = node.calledExpression.trimmedDescription
            match(.secretSink, value: callee, node: Syntax(node), contains: true)
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkCheckpointConformance(node.inheritanceClause, node: Syntax(node))
        return push(node.name.text)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        pop()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkCheckpointConformance(node.inheritanceClause, node: Syntax(node))
        return push(node.name.text)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        pop()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.name.text)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        pop()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.name.text)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        pop()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.extendedType.trimmedDescription)
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        pop()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let signatureHasRows = node.signature.trimmedDescription.contains("Row")
        let bodyReadsRows = node.body?.tokens(viewMode: .sourceAccurate).contains {
            $0.text.hasSuffix("Rows")
        } ?? false
        return push(node.name.text, rowContext: signatureHasRows || bodyReadsRows)
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        pop()
    }

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        let type = normalizedType(node.type.trimmedDescription)
        if type == "UInt16" {
            match(.rawKindParameter, value: "kind:UInt16", node: Syntax(node))
        }
        return .visitChildren
    }

    override func visit(_ node: ArrayTypeSyntax) -> SyntaxVisitorContinueKind {
        if normalizedType(node.trimmedDescription) == "[[String]]" {
            match(.rawTagArray, value: "[[String]]", node: Syntax(node))
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        push("init", rowContext: node.signature.trimmedDescription.contains("Row"))
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        pop()
    }

    private var isRowContext: Bool { rowContextStack.contains(true) }

    private func isRowStorageBase(_ base: String?) -> Bool {
        guard let base else { return false }
        return rowStorageNames.contains { name in
            base == name || base == "self.\(name)"
                || base.hasPrefix("\(name)[") || base.hasPrefix("self.\(name)[")
        }
    }

    private func normalizedType(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "")
    }

    private func checkCheckpointConformance(_ clause: InheritanceClauseSyntax?, node: Syntax) {
        guard clause?.trimmedDescription.contains("NMPLocalAccountCheckpoint") == true else { return }
        match(.customCheckpoint, value: "NMPLocalAccountCheckpoint", node: node)
    }

    private func push(_ symbol: String, rowContext: Bool = false) -> SyntaxVisitorContinueKind {
        symbolStack.append(symbol)
        rowContextStack.append(rowContext)
        return .visitChildren
    }

    private func pop() {
        _ = symbolStack.popLast()
        _ = rowContextStack.popLast()
    }

    private func match(
        _ kind: BoundaryRule.Kind,
        value: String,
        base: String? = nil,
        argumentLabel: String? = nil,
        node: Syntax,
        contains: Bool = false,
        rowContext: Bool = false
    ) {
        for rule in policy.rules where rule.kind == kind {
            guard rule.paths?.contains(where: { Glob.matches($0, path) }) ?? true else {
                continue
            }
            guard rule.symbolContains?.allSatisfy({ symbolStack.joined(separator: ".").contains($0) }) ?? true,
                  rule.fileContains?.allSatisfy(source.contains) ?? true,
                  rule.rowContext.map({ $0 == rowContext }) ?? true else { continue }
            let matchedNames = contains
                ? rule.names.filter(value.contains)
                : rule.names.filter { $0 == value }
            guard !matchedNames.isEmpty else { continue }
            if let baseNames = rule.baseNames {
                guard let base, baseNames.contains(base) else { continue }
            }
            if let labels = rule.argumentLabels {
                guard let argumentLabel, labels.contains(argumentLabel) else { continue }
            }
            for matchedName in matchedNames {
                report(rule, matcher: "\(kind.rawValue):\(matchedName)", at: node)
            }
        }
    }

    private func report(_ rule: BoundaryRule, matcher: String, at node: Syntax) {
        let symbol = symbolStack.joined(separator: ".")
        guard !policy.exceptions.contains(where: {
            $0.rule == rule.id && $0.matcher == matcher
                && Glob.matches($0.path, path) && symbol == $0.symbol
        }) else {
            if let exception = policy.exceptions.first(where: {
                $0.rule == rule.id && $0.matcher == matcher
                    && Glob.matches($0.path, path) && symbol == $0.symbol
            }) {
                let key = "\(exception.rule)|\(exception.path)|\(exception.symbol)|\(exception.matcher)"
                matchedExceptionCounts[key, default: 0] += 1
            }
            return
        }

        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        let line = location.line
        let column = location.column
        let key = "\(rule.id):\(matcher):\(node.position.utf8Offset)"
        guard seen.insert(key).inserted else { return }
        violations.append(
            BoundaryViolation(
                rule: rule.id,
                message: rule.message,
                path: path,
                line: line,
                column: column,
                symbol: symbol,
                matcher: matcher
            )
        )
    }
}

private enum Glob {
    static func matches(_ pattern: String, _ value: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*\\*", with: "\u{0}")
            .replacingOccurrences(of: "\\*", with: "[^/]*")
            .replacingOccurrences(of: "\u{0}", with: ".*")
            .replacingOccurrences(of: "\\?", with: "[^/]")
        return value.range(of: "^\(escaped)$", options: .regularExpression) != nil
    }
}
