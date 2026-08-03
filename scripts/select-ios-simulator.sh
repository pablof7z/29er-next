#!/usr/bin/env bash
# Print the UDID of an available iOS simulator, installing a runtime first if
# the machine has none.
#
# The workflows used to name the destination by `name=iPhone 17 Pro,OS=26.5`
# and got "no available devices matched the request" -- with xcodebuild
# listing NO iOS simulator at all, only the placeholder. That runner does have
# iOS 26.5 and does have an iPhone 17 Pro on it, so the pin was not stale;
# xcodebuild simply could not see the device set. Touching CoreSimulator
# through `simctl` first and then naming an exact UDID resolves it.
#
# Nothing is pinned here either way: a version pinned in this repo against an
# image this repo does not control rots on the image's schedule, silently.
# This resolves whatever the machine actually has and prints both lists, so
# the next failure names itself instead of naming a device.
set -euo pipefail

if ! xcrun simctl list runtimes --json | grep -q 'SimRuntime\.iOS'; then
  echo "No iOS simulator runtime installed; downloading one." >&2
  xcodebuild -downloadPlatform iOS
fi

xcrun simctl list runtimes >&2

udid="$(
  xcrun simctl list devices available --json |
    python3 -c '
import json
import sys

devices = json.load(sys.stdin)["devices"]


def version(runtime):
    """Sort key for `…SimRuntime.iOS-26-5` -> (26, 5)."""
    tail = runtime.rsplit("SimRuntime.iOS-", 1)[-1]
    return tuple(int(part) for part in tail.split("-") if part.isdigit())


available = [
    (version(runtime), entry)
    for runtime, entries in devices.items()
    if "SimRuntime.iOS" in runtime
    for entry in entries
    if entry.get("isAvailable")
]
if not available:
    sys.exit("no available iOS simulator device")

# Newest iOS first, then an iPhone over an iPad, then the highest-sorting
# name -- so one image always yields the same device instead of whatever
# order the JSON happened to arrive in.
def rank(item):
    runtime_version, entry = item
    return (runtime_version, entry["name"].startswith("iPhone"), entry["name"])


print(max(available, key=rank)[1]["udid"])
'
)"

echo "Selected iOS simulator $udid" >&2
xcrun simctl list devices available >&2
echo "$udid"
