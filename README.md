# 29er Next

Greenfield 29er client built on the new [NMP](https://github.com/pablof7z/nmp) engine.

The first vertical slice is intentionally read-only: it discovers public NIP-29 rooms, opens live room timelines, renders current kind:30315 agent activity, and exposes NMP's permanent diagnostics. Durable publishing and identity persistence will arrive through NMP's canonical SDK surfaces instead of being reimplemented in the app.

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
- One scope-bound room query for chat (`kind:9`) and live agent activity (`kind:30315`), filtered by the selected group's `h` tag.
- Kind:30315 replacement and NIP-40 expiry are applied by NMP; Swift only projects the current rows for display.
- Live per-relay NMP diagnostics.

The top relay selector is the next upstream-backed slice. Its signed-in list is the user's NIP-51 relay set (`kind:30002`, `d=nip29`), tracked by [NMP #63](https://github.com/pablof7z/nmp/issues/63). Selected-host read authority is tracked by [NMP #1](https://github.com/pablof7z/nmp/issues/1); the app will not emulate either contract by rebuilding the engine or maintaining a Swift-only relay list.

Tracked by [issue #1](https://github.com/pablof7z/29er-next/issues/1).
