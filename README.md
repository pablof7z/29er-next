# 29er Next

Greenfield 29er client built on the new [NMP](https://github.com/pablof7z/nmp) engine.

The current slice discovers public NIP-29 rooms, opens live room timelines, renders current kind:30315 agent activity, exposes NMP's permanent diagnostics, and lets a locally restored identity send durable management commands to tenex-edge backends. NMP owns the explicit plaintext account checkpoint and restores it on launch.

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

Open `ios/TwentyNinerNext.xcodeproj`, or use XcodeBuildMCP:

```bash
xcodebuildmcp simulator build-and-run \
  --project-path ios/TwentyNinerNext.xcodeproj \
  --scheme TwentyNinerNext
```

The preview bundle identifier is `io.f7z.app29er.next`, so it installs beside the existing 29er app.

## Current slice

- Persistent NMP cache in Application Support.
- App-owned indexer and NIP-29 operator relay configuration.
- Live room metadata query (`kind:39000`) with group identity keyed by host relay plus local group id.
- Read-only subgroup navigation from exactly one child-side `parent` tag in relay-authored metadata. Conflicting or incomplete edges are not inferred; the unlinked group remains visible at the root.
- Independent scope-bound room queries for chat (`kind:9`), membership (`kind:39002`), and live agent activity (`kind:30315`), filtered by the selected group.
- Native room toolbar navigation to direct subchannels and the People roster; Chat remains the primary room screen.
- Kind:30315 replacement and NIP-40 expiry are applied by NMP; Swift only projects the current rows for display.
- Explicit local key import through NMP's `addAccount` and `setActiveAccount` surface. The app retains only the returned public key.
- NMP's opt-in plaintext file provider restores the active signer at launch; the nsec never enters the app's own product state or event database.
- Signing out clears NMP's checkpoint, shuts down the credential-owning engine, and creates a fresh read-only engine over the same event store.
- Signed-in accounts can publish durable kind:9 management commands to room backends and follow NMP's canonical write receipts.
- Live per-relay NMP diagnostics.

Automatic login deliberately favors convenience over credential protection: the NMP SDK stores one plaintext nsec file inside the app sandbox with owner-only permissions. It does not use Keychain, Secure Enclave, hardware-backed encryption, or the canonical event/outbox database. Standard protected vault providers and credential recovery remain separate upstream NMP work.

The top relay selector is the next upstream-backed slice. Its signed-in hosts come from typed NIP-29 composition over the user's NIP-51 remembered-groups list (`kind:10009`), tracked by [NMP #63](https://github.com/pablof7z/nmp/issues/63). Selected-host read authority is tracked by [NMP #1](https://github.com/pablof7z/nmp/issues/1); the app will not emulate either contract by maintaining a Swift-only relay list.

Tracked by [issue #1](https://github.com/pablof7z/29er-next/issues/1).
