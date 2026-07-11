# 29er Next

Greenfield 29er client built on the new [NMP](https://github.com/pablof7z/nmp) engine.

The first vertical slice is intentionally read-only: it discovers public NIP-29 rooms, opens live kind:9 room timelines, and exposes NMP's permanent diagnostics. Durable publishing and identity persistence will arrive through NMP's canonical SDK surfaces instead of being reimplemented in the app.

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
- Live room metadata query (`kind:39000`).
- Scope-bound room timeline query (`kind:9`, `h` tag), with an honest blocked state while the current NMP grammar cannot yet express `h` ([NMP #45](https://github.com/pablof7z/nmp/issues/45)).
- Live per-relay NMP diagnostics.

Tracked by [issue #1](https://github.com/pablof7z/29er-next/issues/1).
