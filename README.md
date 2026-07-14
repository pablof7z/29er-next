# 29er Next

Greenfield 29er client built on the new [NMP](https://github.com/pablof7z/nmp) engine.

The current slice reconstructs a signed-in account's remembered NIP-29 groups through NMP's typed kind 10009 projection, browses the selected host with strict pinned-source evidence, renders live room chat/people state, and lets a locally restored identity send typed group messages and management commands. NMP owns the explicit plaintext account checkpoint and restores it on launch.

## Architecture

- SwiftUI owns presentation, navigation, and which live queries are on screen.
- NMP owns the event store, relay planning, subscription lifecycle, routing, deduplication, persistence, and diagnostics.
- Query handles follow view/task lifetime. There are no timers or polling loops.
- The NMP dependency is pinned as a git submodule; legacy 29er code is not copied into this repository.

## Bootstrap

```bash
git clone --recurse-submodules https://github.com/pablof7z/29er-next.git
cd 29er-next
scripts/bootstrap-nmp.sh
scripts/generate-project.sh
```

Open `ios/TwentyNinerNext.xcodeproj`, or use XcodeBuildMCP. For the native macOS app:

```bash
xcodebuildmcp macos build-and-run \
  --project-path ios/TwentyNinerNext.xcodeproj \
  --scheme TwentyNinerNextMac
```

For the iOS app:

```bash
xcodebuildmcp simulator build-and-run \
  --project-path ios/TwentyNinerNext.xcodeproj \
  --scheme TwentyNinerNext
```

Pull requests run the same generated project through a pinned macOS simulator-test gate. See [Continuous integration](docs/continuous-integration.md) for its toolchain pins, expected runner cost, and caching tradeoffs.

The iOS preview bundle identifier is `io.f7z.app29er.next`, so it installs beside the existing 29er app. The native macOS bundle identifier is `io.f7z.app29er.next.macos`.

## Current slice

- Native macOS split view with an always-visible, expandable channel hierarchy and room content in the detail pane.
- Persistent NMP cache in Application Support.
- App-owned indexer configuration plus one explicitly labeled, read-only operator bootstrap host for signed-out browsing.
- An app-owned host/group selection rendered at the top of the room browser. Signed-in choices come only from NMP's account-scoped `activeAccountDemand` and `decodeRememberedGroups` composition over the canonical NIP-51 kind 10009 winner; the selected host never changes that account demand.
- Live room metadata (`kind:39000`) and directory previews use selected-host pinned NMP demands, with group identity keyed by host relay plus local group id. Changing hosts cancels and replaces only those host-scoped handles.
- Read-only subgroup navigation from exactly one child-side `parent` tag in relay-authored metadata. Conflicting or incomplete edges are not inferred; the unlinked group remains visible at the root.
- Independent bounded, selected-host pinned room queries and evidence for chat (`kind:9` plus `kind:9000`/`kind:9001` notices), membership (`kind:39002`), and live agent activity (`kind:30315`). Each handle follows the room view task and releases its own demand on cancellation.
- Native room toolbar navigation to direct subchannels and the People roster; Chat remains the primary room screen.
- Kind:30315 replacement and NIP-40 expiry are applied by NMP; Swift only projects the current rows for display.
- Explicit local key import through NMP's `addAccount` and `setActiveAccount` surface. The app retains only the returned public key.
- NMP's opt-in plaintext file provider restores the active signer at launch; the nsec never enters the app's own product state or event database.
- Signing out clears NMP's checkpoint, shuts down the credential-owning engine, and creates a fresh read-only engine over the same event store.
- Signed-in accounts can publish durable kind:9 management commands to room backends and follow NMP's canonical write receipts.
- The @ picker includes every durable kind 39002 member, including inactive members, plus status-only pubkeys active in the room. Swift chooses recipients; NMP owns NIP-27 encoding, matching tags, signing, host context, routing, and receipts.
- Live per-relay NMP diagnostics.

Automatic login deliberately favors convenience over credential protection: the NMP SDK stores one plaintext nsec file inside the app sandbox with owner-only permissions. It does not use Keychain, Secure Enclave, hardware-backed encryption, or the canonical event/outbox database. Standard protected vault providers and credential recovery remain separate upstream NMP work.

Remember/forget is deliberately absent. Safe edits to the kind 10009 replaceable list remain blocked on [NMP #50](https://github.com/pablof7z/nmp/issues/50), which must preserve source-scoped base evidence and unknown/private items. The app never rebuilds that list from its public projection and never keeps an optimistic Swift mirror.

The current typed kind 9 composer is NMP-owned end to end. Broader immutable draft/context composition for other protocol-owned event types remains tracked by [NMP #45](https://github.com/pablof7z/nmp/issues/45); Swift does not add protocol validation, raw tags, relay routing, signing, retries, or compatibility shims while that contract remains open.

Tracked by [issue #1](https://github.com/pablof7z/29er-next/issues/1).
