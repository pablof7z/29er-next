# Handoff: adopt NMP's landed NIP-29 work

You are picking up the job of adopting what NMP has just finished building for
NIP-29. Read `AGENTS.md` in this repo first — it governs how you work here, and
nothing below overrides it.

## Where things stand

This app tracks NMP master through `Dependencies/nmp` (see
`scripts/bootstrap-nmp.sh`), and `.github/workflows` runs a nightly build/test
against NMP master that opens a tracking issue when a break lands. So unlike a
pinned consumer, you are probably **not** facing a wall of compile errors.

That is exactly why this handoff exists. NMP closed its NIP-29 capstone epic
(#1140) — real multi-relay Rust and Swift consumer apps proving the protocol
against real relays — and the new capabilities are things this app can now
*use*, not just survive. Compiling is not adopting.

**Before anything else, establish the actual baseline.** Update
`Dependencies/nmp` to current NMP master, build, and run the simulator tests.
Report what you find. If the nightly has been red, read its tracking issue
first rather than rediscovering the break.

## The headline: this app is hard-wired to one relay

`ios/project.yml` sets a single `NMPGroupRelay: wss://nip29.f7z.io`, read in
`ios/Sources/OperatorConfiguration.swift:31` as one string.

The NIP-29 door is now a *relay scope* over a host list:

    NMPRelayScope.on([String]) throws -> NMPRelayScope     // empty set throws .emptyRelayScope
        .group(_ groupID: String) -> NMPGroup              // narrows; contacts nothing
        .groupsWhere(_ predicate: NMPGroupPredicate) throws -> NMPLiveQuery

    NMPGroup
        .read(_ selection: NMPFilter) throws -> NMPLiveQuery
        .validateContext(_ event: NMPSignedEvent) throws
        .publish(...) / .publishSigned(...)
        .joinRequest / .leaveRequest / .addUser / .removeUser
        .editMetadata / .deleteEvent / .createGroup / .deleteGroup / .createInvite

    NMPGroupPredicate — composable: .union(...) / .intersect(...) / .minus(...)

`groupsWhere` folds **one complete branch per host into ONE `NMPLiveQuery`**.
`NMPEngine.observe(_:)` takes that directly — the app never merges a per-host
demand list itself. If any code here fans out across relays and combines the
results by hand, that is now the library's job and the hand-rolled version is
very likely wrong in ways described below.

Decide deliberately whether `NMPGroupRelay` should become a host *list*. Do not
just widen the config because you can — a group genuinely hosted on one relay
is a legitimate configuration. But the single-string shape currently makes
multi-relay impossible to express, and that is the capability NMP just spent
its capstone proving.

## Behaviour that changed underneath you

These are the ones a green build will hide.

**Multi-relay provenance is now correct (NMP #1221/#1222).** Until days ago a
row's sources meant *"relays that happened to deliver this to me"*, not
*"relays in scope that hold it"* — reconciliation was seeded from a
relay-agnostic local store, so a relay that also held an event another relay
delivered first was never recorded as a source for it. This was found by the
capstone harness on its first full run. If anything in this app shows or
reasons about which relay a row came from, the values are now different, and
correct.

**A locally accepted write shows immediately (NMP #1182/#1191).** Provenance
always distinguishes "in cache" from "came from these relays (zero or more)". A
cache-only row reports *yes in cache, relays: []* — that is a real state, not a
missing value or a loading placeholder. Visibility under a host pin is decided
by ours-versus-foreign, not carried-versus-uncarried. If this app shows a
spinner until a relay acknowledges the user's own message, it no longer needs
to — and the optimistic path is now the governed behaviour rather than a trick.

**`NMPLiveQuery` is a canonical branch set, not an ordered list (NMP
#1189/#1206).** It is built only through `single` and `union`; `union`
flattens, sorts, deduplicates, and can refuse. Equality and hashing are over
the canonical set, so two queries declared in different orders are the same
value *and* the same dictionary key. Concretely:

- You cannot construct one memberwise any more; the public initializer and the
  mutable branch collection were deleted outright.
- **`branches[i]` names the branch that `evidence[i]` reports on.** If you index
  per-branch evidence positionally — and every surface does — that
  correspondence is load-bearing. Never reorder one without the other.
- If this app keyed a dictionary of "queries I am already watching" off a query
  value, that lookup now behaves correctly across declaration orders. Check
  whether anything worked around the old behaviour.

**Refusals happen where you declare, not where you watch.** An empty query, a
zero cap, a nested cap, and more branches than the ceiling are all typed errors
raised at construction, with no engine, account, or relay involved. Building
queries at startup is now safe in a way it wasn't.

## Suggested order

1. Update `Dependencies/nmp` to current master; build; run simulator tests.
   Report the true baseline before changing anything.
2. Survey where this app touches NIP-29 and live queries. `RoomDirectoryModel`,
   `NMPQueryOpening`, `AppEngineBootstrap`, `InboxModel`, `RoomView`, and
   `ObservationModelTests` are the obvious starting points, but confirm rather
   than trusting this list.
3. Take the behaviour changes one at a time, each independently verifiable.
   Prefer several small reviewable changes over one sweeping adoption commit.
4. For anything user-visible — optimistic send, per-relay provenance display,
   multi-relay room directory — prove it against a real relay, not only a unit
   test. NMP ships a real-relay harness at `tools/nip29-consumer-harness/` in
   its repo (two seeded Croissant relays, groups hosted on one or both with
   conflicting metadata and divergent membership). It is the closest thing to a
   truthful fixture for this work. Use its **docker** backend.

## Things that will cost you time if nobody says them

- **Push early, even WIP.** Several pieces of finished work were found stranded
  on local disk in the NMP repo recently because their owner went away.
- **NMP master advances fast.** Re-sync `Dependencies/nmp` before you finish; a
  long-running adoption will otherwise be stale by the time it lands.
- **NMP deletes rather than deprecates.** There is no compatibility shim for
  anything above, by explicit policy. If something you relied on is gone, it is
  gone on purpose — find the replacement rather than reconstructing the old
  shape locally.
- Do not weaken a test to make an adoption land. If a test fails against the
  new behaviour, decide whether the test encoded the *old bug*; say which,
  explicitly.

## Report

State: the true baseline after re-syncing NMP; which capabilities you adopted,
which you deliberately skipped and why; anything user-visible that changed;
whether `NMPGroupRelay` should become a host list and your reasoning either
way; and anything you could not verify against a real relay.

If adoption turns out to need a product decision rather than an engineering one
— particularly whether this app should present per-relay provenance to users at
all, or how a room hosted on disagreeing relays should look — stop and say so
rather than inventing an answer. That is a good outcome, not a failure.
