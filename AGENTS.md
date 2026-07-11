# Repository guidance

## Workflow

- Every implementation unit starts from a GitHub issue and lands through a ready-for-review PR.
- Work only from an agent-owned git worktree. Never implement from the shared root checkout.
- PR descriptions include a TLDR, detailed overview, and tradeoffs or assumptions.
- Validate the running iOS result when the change is user-visible.

## Product boundary

This app consumes `pablof7z/nmp`, the greenfield embeddable Nostr engine. It does not consume or copy the legacy `nostr-multi-platform` app framework.

- NMP owns event validation/storage, provenance, replacement/deletion/expiry, relay planning, subscription lifecycle, routing, sync, write receipts, and diagnostics.
- The app owns presentation, navigation, product state, operator configuration, and which queries exist.
- Swift may format raw values for display. It must not implement relay selection, retry, signing, protocol validation, cache invalidation, or subscription management.
- Do not add an app-local optimistic write mirror. Pending writes must eventually arrive through NMP's canonical store path.
- Do not persist an nsec in Swift. Identity storage waits for NMP's governed signer-provider surface.

## Reactivity

- No polling, fixed-rate refresh, or sleep-and-check loops.
- Observe NMP through its native `AsyncSequence` handles.
- Scope room queries to the view task that needs them; cancellation must release demand.
- Keep delivered state bounded to the active room and app chrome.

## Source hygiene

- Source files have a 300-line soft limit and 500-line hard limit.
- Documentation and declarative files have an 800-line hard limit.
- No TODO comments or temporary compatibility paths. Track future work in GitHub Issues.
