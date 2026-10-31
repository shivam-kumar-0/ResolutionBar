# ResolutionBar Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver a native menu bar resolution switcher and a GitHub-ready source package.

**Architecture:** A pure Swift core describes display modes, builds menu sections, and coordinates guarded preview/commit/rollback through a display-service protocol. An AppKit executable implements Core Graphics transactions, display notifications, dropdown, and confirmation window.

**Tech Stack:** Swift 5 language mode with Swift tools 5.9+, AppKit, Core Graphics, SwiftPM, Swift Testing, shell packaging.

**Spec:** ../specs/2026-10-31-resolutionbar-design.md

## Global Constraints

- macOS 13 or later; no external dependencies, Dock icon, network service, analytics, or custom modes.
- Single/extended displays selectable; mirrored groups read-only, including their primary.
- 15-second preview, sleep-inclusive deadline, Keep requests permanent scope; guarded target-only rollback.
- Do not publish a repository/release or change live display resolution during verification.
- Source and deliverables under outputs; temporary build products/logs under work.

## Review Focus

- Mirror primary with inactive secondary must remain read-only: task 1 menu policy and task 3 online enumeration inspection.
- Stale display IDs after reconnection must never target a replacement: task 2 connection-generation test.
- Own notifications must not cancel a preview; external mode/topology changes must: task 2 reconciliation tests.
- Expired confirmation after sleep must revert and cannot save: task 2 injected-clock tests.
- Failed permanent save and failed rollback must be visible and end preview: task 2 failure tests.

### Task 1: Display model and menu policy

**Files:** Package.swift; Sources/ResolutionCore/DisplayModel.swift; Tests/ResolutionCoreTests/DisplayModelTests.swift.

**Interfaces:** Produces DisplayMode, DisplaySnapshot, DisplayFrame, DisplayMenuSection, DisplayMenu.sections(_:). Mode carries its native ID, logical/render dimensions, refresh rate, and safety flags. Snapshot carries native ID, hardware identity, connection generation, active/main/built-in/mirror state, frame, current mode, and modes.

- [ ] Write tests for current-mode preservation, HiDPI/refresh distinctions, safety filtering, unknown refresh, direct/extended grouping, duplicate names, mirrors, and empty displays.
- [ ] Run tests with stub menu policy; expect behavior assertion failures.
- [ ] Implement normalization, labels, and section construction.
- [ ] Run the model tests; expect all to pass.

### Task 2: Preview and recovery coordinator

**Files:** Sources/ResolutionCore/SwitchCoordinator.swift; Tests/ResolutionCoreTests/SwitchCoordinatorTests.swift.

**Interfaces:** Consumes task 1 types. Produces DisplayService.snapshot() throws -> [DisplaySnapshot], DisplayService.apply(display:mode:scope:) throws, ChangeScope, SwitchCoordinator.select(display:mode:), keep(), revert(), tick(), reconcile(), pending, isBusy, and remainingSeconds. Takes an injected clock closure. Native service must repeat stale-state validation before mutation.

- [ ] Write fake-service tests for no-op/current, normal preview, keep, expiry, expired Keep, overlapping changes, stale identity/generation/mode, mirror rejection, disconnect, external mode/geometry, own callbacks, and apply/save/rollback failures.
- [ ] Run coordinator tests against stub behavior; expect assertion failures.
- [ ] Implement target-only guarded recovery, post-apply topology snapshot, expected own transitions before mutation, sleep-inclusive deadline checks, and save failure rollback.
- [ ] Run the whole core suite; expect all to pass.

### Task 3: Native app and distribution

**Files:** Sources/ResolutionBar/{main.swift,NativeDisplayService.swift,AppController.swift,ConfirmationWindow.swift}; scripts/{build-app.sh,test.sh}; .github/workflows/ci.yml; README.md; LICENSE; .gitignore.

**Interfaces:** NativeDisplayService implements task 2 protocol using online topology, active targets, display UUID plus connection generation, fresh mode validation, and configuration transactions. AppController consumes model sections and coordinator, and owns status menu, queued callbacks, wake handling and confirmation UI. Read-only --diagnose JSON and --demo fixtures support verification without hardware changes; demo UI must never invoke the real display service.

- [ ] Wire AppKit dropdown and confirmation to the tested core; compile the executable.
- [ ] Run read-only diagnostics against current hardware; inspect modes and mirror/active flags.
- [ ] Provide isolated fixture demo for single, multiple, mirrored, and no-display states; smoke-test menu construction and confirmation wiring without changing real modes.
- [ ] Build arm64 and x86_64 release slices, combine to a universal executable, construct an LSUIElement app bundle, ad-hoc sign, verify signature and plist, and package ZIP.
- [ ] Add MIT license attributed to ResolutionBar contributors, README covering build/install/Gatekeeper/limits/manual checks, and CI test/universal-build workflow. Public release upload remains manual.
- [ ] Request independent final code review, fix important findings with regression tests, and re-run relevant verification.
- [ ] Package source ZIP without .git/build products and write verification results with actual hardware-test limits.

## Execution decisions

The user approved the design and asked to proceed. Implement inline without another approval round. This is a new repository on feat/resolutionbar in its own output directory, so there is no existing checkout to isolate. Record progress in work/verification/progress.md; keep logs outside the deliverable source tree. Commit tested milestones when local Git permits. No remote is configured and nothing is published.
