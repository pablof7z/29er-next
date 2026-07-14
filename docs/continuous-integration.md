# Continuous integration

Pull requests targeting `main` run the `TwentyNinerNext` scheme's unit tests on an iOS simulator. The workflow checks out the proposed merge, initializes the pinned NMP submodule, builds its XCFramework, generates `ios/TwentyNinerNext.xcodeproj` from `ios/project.yml`, and runs tests without committing generated project files.

## Pinned environment

The workflow deliberately names its mutable inputs:

- GitHub's standard `macos-15` arm64 runner rather than `macos-latest`.
- Xcode 16.4 through `DEVELOPER_DIR`, with an iPhone 16 Pro on iOS 18.5.
- `actions/checkout` v7.0.0 by its full commit SHA. GitHub documents a full-length SHA as the only immutable way to consume an action.
- XcodeGen 2.45.4 by release URL and SHA-256 digest.

`macos-15` is an OS/architecture pin, not a frozen machine image: GitHub refreshes the installed image over time. Before changing the runner label, Xcode, simulator runtime, checkout SHA, or XcodeGen version, verify the combination against the current [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [macOS 15 arm64 image manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md), [secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use), [checkout releases](https://github.com/actions/checkout/releases), and [XcodeGen releases](https://github.com/yonaskolb/XcodeGen/releases). Update the workflow pins together and confirm the PR gate passes before merging.

## Runner-minute cost

This repository is public. GitHub's standard hosted runners are currently free and unlimited for public repositories, so the expected billed runner cost is **$0 per pull-request run**. A run still occupies one macOS runner for its wall-clock duration, and a new commit cancels the older run for the same pull request.

Until Actions provides hosted-run timing, budget **15–30 macOS runner-minutes per cold pull-request run**. The July 14, 2026 local baseline spent 12 minutes 18 seconds building NMP from an empty submodule and 52 seconds building and running 88 simulator tests; the range allows for hosted hardware, dependency download, and project-resolution variance.

If the repository becomes private, the same job consumes included Actions minutes first and is then billed at GitHub's current standard macOS rate. As of July 14, 2026, GitHub lists **$0.062 per minute** and rounds each job up to the next whole minute. The expected 15–30 minute range would therefore cost $0.93–$1.86 per run after the included allowance. Recheck the [Actions runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing) before using those estimates for a budget.

## Caching decision

The initial gate does not restore or save a dependency cache. That makes every run a clean proof that the pinned NMP submodule can build and the Swift package graph can resolve. It also avoids treating cached Rust outputs, generated Swift bindings, or XCFramework slices as trusted build inputs on pull requests from forks.

The tradeoff is repeated NMP compilation and Swift package resolution, so the gate uses more runner time and network traffic. Revisit caching after measuring real Actions runs. A future cache should be restore-only for untrusted pull requests and keyed at minimum by runner OS and architecture, selected Xcode version, NMP submodule commit, Rust lockfile, and Swift package resolution inputs. GitHub notes that cache contents are not signed, can be read by eligible pull requests, are evicted after inactivity, and count against repository cache storage; see the [dependency caching overview](https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching) and [cache reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
