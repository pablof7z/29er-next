import Foundation

public struct BoundaryPolicy: Codable, Sendable {
    public static let requiredRuleIDs: Set<String> = [
        "NMP001", "NMP002", "NMP003", "NMP004", "NMP005", "NMP006", "NMP007", "NMP008"
    ]
    public static let requiredMatchers: [String: Set<String>] = [
        "NMP001": [
            "identifier:WriteIntent", "identifier:NMPUnsignedEvent",
            "unsignedPayload:payload.unsigned",
        ],
        "NMP002": ["memberAccess:signEvent"],
        "NMP003": [
            "identifier:URLSession", "identifier:URLRequest",
            "identifier:HTTPURLResponse", "identifier:SHA256",
            "stringContains:/upload",
        ],
        "NMP004": [
            "memberAccess:kind", "memberAccess:tags",
            "stringContains:(?:npub|nprofile|note|nevent|naddr)",
            "rawTagArray:[[String]]", "rawKindParameter:kind:UInt16",
        ],
        "NMP005": [
            "integerArgument:7", "integerArgument:9",
            "integerArgument:10009", "integerArgument:24242",
        ],
        "NMP006": [
            "identifier:NMPStoreEpoch", "memberAccess:removeItem",
            "stringContains:nmp-store-epoch",
        ],
        "NMP007": [
            "identifier:NMPInsecureFileAccountStore", "stringContains:.nsec",
            "secretSink:set", "secretSink:write", "secretSink:SecItemAdd",
            "secretSink:SecItemUpdate", "customCheckpoint:NMPLocalAccountCheckpoint",
        ],
        "NMP008": [
            "importName:NMPFFI", "importName:NostrMultiPlatform", "importName:NostrSDK",
        ],
    ]
    private static let permanentExceptionOwners: Set<String> = [
        "NIP-07 browser consent bridge",
        "NMP Blossom authorization flow",
        "NMP Blossom authorization input",
        "Blossom error presentation",
        "Legacy secret cleanup",
        // `NMPGroupMetadata` types the three rows NIP-29 defines and carries
        // the record's complete row list verbatim, in its own words, "so that
        // reading a row NIP-29 core does not define (a `parent`, say) needs no
        // hand-parser here". Reading one is therefore the supported contract,
        // not a gap: there is no upstream issue to name because NMP is not
        // going to define somebody else's convention.
        "NMP group-metadata verbatim rows",
    ]
    public let schemaVersion: Int
    public let rules: [BoundaryRule]
    public let exceptions: [BoundaryException]

    public init(
        schemaVersion: Int,
        rules: [BoundaryRule],
        exceptions: [BoundaryException]
    ) {
        self.schemaVersion = schemaVersion
        self.rules = rules
        self.exceptions = exceptions
    }

    /// The same rules with nothing excused, for regeneration. A drifted
    /// exception list makes the normal scan throw on occurrence counts before
    /// it can report anything, so rebuilding the list from a drifted state is
    /// impossible unless the rules can be run on their own.
    public var withoutExceptions: BoundaryPolicy {
        BoundaryPolicy(schemaVersion: schemaVersion, rules: rules, exceptions: [])
    }

    public static func load(from url: URL) throws -> BoundaryPolicy {
        let policy = try JSONDecoder().decode(
            BoundaryPolicy.self,
            from: Data(contentsOf: url)
        )
        guard policy.schemaVersion == 1 else {
            throw BoundaryPolicyError.unsupportedSchema(policy.schemaVersion)
        }
        let ruleIDs = Set(policy.rules.map(\.id))
        guard Self.requiredRuleIDs.isSubset(of: ruleIDs) else {
            throw BoundaryPolicyError.missingRequiredRules(
                Self.requiredRuleIDs.subtracting(ruleIDs).sorted()
            )
        }
        let configuredMatchers = Dictionary(
            grouping: policy.rules.filter(Self.hasRequiredScope),
            by: \.id
        )
            .mapValues { rules in
                Set(rules.flatMap { rule in
                    rule.names.map { "\(rule.kind.rawValue):\($0)" }
                })
            }
        for (rule, expected) in Self.requiredMatchers {
            let missing = expected.subtracting(configuredMatchers[rule, default: []])
            guard missing.isEmpty else {
                throw BoundaryPolicyError.missingRequiredMatchers(rule, missing.sorted())
            }
        }
        for rule in policy.rules {
            guard !rule.message.isEmpty, !rule.names.isEmpty else {
                throw BoundaryPolicyError.emptyRuleMatcher(rule.id)
            }
        }
        for exception in policy.exceptions {
            guard ruleIDs.contains(exception.rule) else {
                throw BoundaryPolicyError.unknownExceptionRule(exception.rule)
            }
            guard !exception.path.isEmpty,
                  !exception.symbol.isEmpty,
                  !exception.matcher.isEmpty,
                  !exception.owner.isEmpty,
                  !exception.rationale.isEmpty else {
                throw BoundaryPolicyError.incompleteException(exception.rule)
            }
            guard !exception.path.contains("*"),
                  !exception.path.contains("?") else {
                throw BoundaryPolicyError.wildcardException(exception.path)
            }
            guard exception.expectedOccurrences > 0 else {
                throw BoundaryPolicyError.invalidExceptionOccurrences(exception.rule)
            }
            guard Self.permanentExceptionOwners.contains(exception.owner)
                    || Self.isIssueOwner(exception.owner) else {
                throw BoundaryPolicyError.invalidExceptionOwner(exception.owner)
            }
        }
        let exceptionKeys = policy.exceptions.map {
            "\($0.rule)|\($0.path)|\($0.symbol)|\($0.matcher)"
        }
        guard Set(exceptionKeys).count == exceptionKeys.count else {
            throw BoundaryPolicyError.duplicateException
        }
        return policy
    }

    private static func isIssueOwner(_ value: String) -> Bool {
        value.range(
            of: "^(NMP|29er-next|TTS29) issue [1-9][0-9]*$",
            options: .regularExpression
        ) != nil
    }

    private static func hasRequiredScope(_ rule: BoundaryRule) -> Bool {
        guard rule.paths == nil,
              rule.baseNames == nil,
              rule.symbolContains == nil else { return false }

        switch (rule.id, rule.kind) {
        case ("NMP003", .identifier):
            return Set(rule.fileContains ?? []) == ["Blossom"]
                && rule.argumentLabels == nil && rule.rowContext == nil
        case ("NMP004", .memberAccess):
            return rule.fileContains == nil
                && rule.argumentLabels == nil && rule.rowContext == true
        case ("NMP005", .integerArgument):
            return rule.fileContains == nil
                && Set(rule.argumentLabels ?? []) == ["kind"] && rule.rowContext == nil
        case ("NMP006", .memberAccess):
            return Set(rule.fileContains ?? []) == ["nmp.redb"]
                && rule.argumentLabels == nil && rule.rowContext == nil
        default:
            return rule.fileContains == nil
                && rule.argumentLabels == nil && rule.rowContext == nil
        }
    }
}

public struct BoundaryRule: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case importName
        case identifier
        case memberAccess
        case stringContains
        case integerArgument
        case unsignedPayload
        case secretSink
        case customCheckpoint
        case rawTagArray
        case rawKindParameter
    }

    public let id: String
    public let message: String
    public let kind: Kind
    public let names: [String]
    public let baseNames: [String]?
    public let argumentLabels: [String]?
    public let paths: [String]?
    public let symbolContains: [String]?
    public let fileContains: [String]?
    public let rowContext: Bool?

    public init(
        id: String,
        message: String,
        kind: Kind,
        names: [String],
        baseNames: [String]? = nil,
        argumentLabels: [String]? = nil,
        paths: [String]? = nil,
        symbolContains: [String]? = nil,
        fileContains: [String]? = nil,
        rowContext: Bool? = nil
    ) {
        self.id = id
        self.message = message
        self.kind = kind
        self.names = names
        self.baseNames = baseNames
        self.argumentLabels = argumentLabels
        self.paths = paths
        self.symbolContains = symbolContains
        self.fileContains = fileContains
        self.rowContext = rowContext
    }
}

public struct BoundaryException: Codable, Sendable {
    public let rule: String
    public let path: String
    public let symbol: String
    public let matcher: String
    public let owner: String
    public let rationale: String
    public let occurrences: Int?
    public var expectedOccurrences: Int { occurrences ?? 1 }

    public init(
        rule: String,
        path: String,
        symbol: String,
        matcher: String,
        owner: String,
        rationale: String,
        occurrences: Int? = nil
    ) {
        self.rule = rule
        self.path = path
        self.symbol = symbol
        self.matcher = matcher
        self.owner = owner
        self.rationale = rationale
        self.occurrences = occurrences
    }
}

public enum BoundaryPolicyError: Error, CustomStringConvertible {
    case unsupportedSchema(Int)
    case missingRequiredRules([String])
    case missingRequiredMatchers(String, [String])
    case emptyRuleMatcher(String)
    case unknownExceptionRule(String)
    case incompleteException(String)
    case wildcardException(String)
    case invalidExceptionOccurrences(String)
    case invalidExceptionOwner(String)
    case duplicateException

    public var description: String {
        switch self {
        case .unsupportedSchema(let version):
            "Unsupported boundary-policy schema \(version)."
        case .missingRequiredRules(let rules):
            "Boundary policy is missing required rule(s): \(rules.joined(separator: ", "))."
        case .missingRequiredMatchers(let rule, let matchers):
            "Boundary rule \(rule) is missing required matcher(s): \(matchers.joined(separator: ", "))."
        case .emptyRuleMatcher(let rule):
            "Boundary rule \(rule) must have a message and at least one matcher name."
        case .unknownExceptionRule(let rule):
            "Boundary exception references unknown rule \(rule)."
        case .incompleteException(let rule):
            "Boundary exception for \(rule) requires path, symbol, owner, and rationale."
        case .wildcardException(let path):
            "Boundary exceptions must use an exact source path, not \(path)."
        case .invalidExceptionOccurrences(let rule):
            "Boundary exception for \(rule) must expect at least one occurrence."
        case .invalidExceptionOwner(let owner):
            "Boundary exception owner must be a permanent contract or exact issue identifier: \(owner)."
        case .duplicateException:
            "Boundary policy contains duplicate exception keys."
        }
    }
}
