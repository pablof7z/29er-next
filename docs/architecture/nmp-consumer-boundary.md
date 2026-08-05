# NMP consumer boundary

29er Next is a product client of NMP, not a second Nostr engine.

The policy deliberately pins no NMP revision. `scripts/bootstrap-nmp.sh`
clones NMP **master**, which moves daily, so a gate that refused to run
unless the checkout matched a recorded revision would go red on somebody
else's commit and stay red. What the rules describe is this app's own
source, and that is what they are checked against.

An earlier audit from `b99f9d41f9670263e0a89688f47700a701448749` covered NMP's
Swift consumer package (`Packages/NMP/Sources/NMP`), the only surface this
policy governs. That range changes the write plane but adds no ungoverned
consumer capability:

- `WritePayload.unsigned(pubkey:createdAt:kind:tags:content:)` became
  `WritePayload.event(kind:tags:content:createdAt:)` (NMP #1005). The app no
  longer states an author or a clock; it still states a raw `kind` and raw
  `tags`, so `NMP001`, `NMP004` and `NMP005` still own those call sites.
- `WriteRouting.authorOutbox` became `.auto` plus `.explicit(relays:)`
  (NMP #1006), and `identityOverride: String?` became
  `Identity { .active, .explicit(pubkey:) }` (NMP #1009). Both are new
  app-reachable escape hatches that carry raw relay URLs and a raw pubkey
  across the boundary. Neither needs a new rule: a `WriteRouting` or
  `Identity` value is only meaningful inside a `WriteIntent`, and `NMP001`
  already flags every `WriteIntent` construction by identifier, so each use
  lands on a site that already requires a reviewed exception.
- `WriteStatus.superseded`, `NMPWriteCancellationError.alreadySuperseded` and
  `NMPError.replaceableEditHasNoWireForm` are receipt and error additions.
  Rendering NMP receipts is app-owned, so no rule changes.
- `commentIntent` lost `authorPubkey:`/`createdAt:` and
  `NMPFollowActionFailure` lost `baseHasWrongAuthor`/`timestampExhausted`.
  The app calls neither.

No exception was added, removed, or widened by this re-audit.

## Ownership

Swift owns presentation, navigation, product state, operator configuration,
the queries the product needs, bounded `NMPDemand` values, user choices, and
rendering of NMP receipts and diagnostics.

NMP's supported `NMP`, `NMPContent`, and `NMPUI` facades own:

- event and protocol validation;
- event composition, signing, timestamps, tags, and replacement semantics;
- group contextualization and relay routing;
- subscription lifecycle, retry, canonical storage, and cache invalidation;
- durable write obligations, receipt facts, and outcome ambiguity;
- Blossom authorization, networking, redirects, integrity, and descriptors;
- shared Nostr content and protocol parsing.

Production Swift must not import `NMPFFI`, generated bindings, or the legacy
application framework. A missing facade is an upstream issue, not permission
to build a raw event, parser, relay client, retry loop, or storage workaround.

## Supported app seams

The app may construct `NMPFilter` and `NMPDemand` because query selection and
bounds are product policy. NMP still owns relay planning, live subscriptions,
canonical rows, and evidence after that declaration.

Observations are view-task scoped and consumed through NMP's `AsyncSequence`
handles. Cancellation releases demand. There is no polling or app-local event
mirror.

Receipt statuses and diagnostics are facts for presentation. Swift may retain
receipt correlation required by product lifecycle and display exact failures;
it must not retry or manufacture delivery success.

Raw row fields may be formatted for display. Branching on event kinds or tags
to reconstruct NIP semantics requires a typed Rust-backed projection.

## Mechanical gate

`tools/NMPBoundaryLint` parses every production Swift file with pinned
SwiftSyntax. The fixtures are syntactic regression tests; they do not
typecheck an NMP consumer. The production command verifies that its scan
root covers every application source path in `ios/project.yml`, so a new
source directory cannot pass by not being looked at. Its declarative policy
reports:

- `NMP001`: raw event or write-intent construction;
- `NMP002`: direct signing outside reviewed NMP-owned draft flows;
- `NMP003`: app-local Blossom transport or cryptography;
- `NMP004`: protocol parsing from raw row kinds or tags;
- `NMP005`: raw protocol-kind composition or semantic editing;
- `NMP006`: app-owned NMP store epochs or recovery;
- `NMP007`: secret-key persistence in Swift;
- `NMP008`: FFI, generated-binding, or legacy imports.

Each diagnostic has a failing historical fixture and a passing syntactic
example. CI runs those tests and then the production-tree scan before it
builds anything, because neither needs the Rust toolchain and a boundary
regression should be reported in a minute rather than after a full NMP
build.

Exceptions live only in
`tools/NMPBoundaryLint/Policy/nmp-boundary.json`. An exception must name the
exact path, enclosing symbol, matcher, expected occurrence count, owner, and
rationale. A missing upstream surface must name an accepted repository issue
identifier. CI rejects wildcard paths, duplicate exceptions, changed occurrence
counts, and unknown permanent owners; inline suppressions are not supported.
The exception is deleted when that surface lands.
Permanent exceptions are limited to supported facade contracts, such as
NIP-07 consent signing, NMP's documented Blossom draft-sign-validate flow, and
deletion-only cleanup of the former plaintext account file.

Run the same gate locally:

```sh
swift test --package-path tools/NMPBoundaryLint
swift run --package-path tools/NMPBoundaryLint nmp-boundary-lint \
  --root ios/Sources \
  --project ios/project.yml \
  --policy tools/NMPBoundaryLint/Policy/nmp-boundary.json \
  --repository-root .
```

When a change legitimately moves an exception -- a file is renamed, a
function is split, a gap upstream closes -- regenerate the list rather than
hand-editing occurrence counts:

```sh
swift run --package-path tools/NMPBoundaryLint nmp-boundary-lint \
  --root ios/Sources \
  --project ios/project.yml \
  --policy tools/NMPBoundaryLint/Policy/nmp-boundary.json \
  --repository-root . \
  --format exceptions
```

Each row is `rule`, path, enclosing symbol, matcher. Every row still needs an
owner and a rationale written by hand: the tool can say what the app does,
never whether it is allowed to.
