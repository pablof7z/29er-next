import SwiftSyntax

final class RowStorageCollector: SyntaxVisitor {
    private(set) var names: Set<String> = []

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let type = binding.typeAnnotation?.type,
                  type.tokens(viewMode: .sourceAccurate).contains(where: {
                      $0.tokenKind == .identifier("Row")
                  }),
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            names.insert(pattern.identifier.text)
        }
        return .visitChildren
    }
}
