# ResolutionBar — proposed first release

Status: approved and implemented; the user subsequently requested the compact macOS-style preset picker described below.

## Purpose

A lightweight, open-source macOS menu bar app for changing display resolution without opening System Settings. Clicking the menu bar icon opens a native dropdown. No account, network service, analytics, or third-party runtime is required.

## Proposed defaults

These are implementation recommendations, not preferences the user has already confirmed.

- Name: ResolutionBar.
- macOS 13 or later; Swift with an AppKit status item and native menus. A small native window handles Keep/Revert confirmation.
- No Dock icon or main window. No external dependencies.
- Each change is previewed immediately, with 15 seconds to Keep or Revert. Expiry restores the previous configuration. Quit during a preview also reverts it; app-scoped preview changes provide fallback on process termination.
- Normal rollback restores only the target mode, guarded by the same connection generation, unambiguous display identity, and unchanged preview mode. Never call the user-wide permanent-configuration restore API. The app-scoped termination fallback restores session/permanent configuration and may differ from the exact pre-preview state.
- Keep requests the permanent display-configuration scope, so quitting the app does not intentionally restore the old setting. macOS may limit some configurations to the current login session even when the permanent request succeeds; do not promise every mode survives logout. Saving can fail and must be reported.
- Only modes macOS exposes for the display are available; no custom timings, virtual displays, or private APIs.
- First release excludes global shortcuts, favorites, automatic resolution rules, startup launch settings, brightness, rotation, and display arrangement editing.

## Display cases

| Case | Required behavior |
| --- | --- |
| One built-in or external display | Show its name, current mode, and a directly selectable resolution list. |
| Multiple extended displays | Group resolutions under each display name in the same dropdown. Change only the selected display's mode and do not intentionally edit display arrangement. macOS may reposition displays to accommodate changed bounds. Mark the main display and built-in display. |
| Identical display names | Add a display number to distinguish connected instances; the current connection's label is not a persistent identity. |
| MacBook lid closed | Show only active displays. Do not show the inactive built-in display as an available target. |
| Mirrored displays | Detect and label the mirror group. For v1, disable resolution actions for that group and explain that independent switching requires extended mode. Do not break mirroring or promise independent resolutions. Extended displays outside the group remain usable. |
| Retina/scaled modes | Label logical size and HiDPI versus low resolution. Preserve refresh-rate variants. Do not merge modes merely because logical width/height match. |
| Refresh rate reported as zero | Omit the refresh-rate number rather than displaying 0 Hz or inventing a rate. |
| Connect/disconnect, wake, or changes elsewhere | Refresh on display notifications and whenever the dropdown opens; avoid continuous polling. Revalidate the selected display and mode immediately before applying. |
| Disconnect or topology change during preview | Cancel the pending Keep action. Restore previous modes only on still-connected matching display identities; do not apply an old display ID to a different device or restore stale arrangement/mirroring. Show an understandable notice if full restoration is impossible. |
| Unsupported, read-only, remote, or virtual display | Expose selectable modes only when available; otherwise show an explanatory disabled item. A failed change reports the failure and does not claim success. |
| No displays or enumeration failure | Keep Quit accessible and show an explanatory item; opening the menu retries enumeration. |

## Menu and switching behavior

- Native dropdown with normal keyboard navigation and checkmarks for the current mode.
- One display: resolutions appear directly. More than one display: named sections in a scrollable native menu; no additional app window to select a display.
- Each row identifies logical resolution, HiDPI/low resolution, and refresh rate when known. Exact duplicates can be collapsed only when their user-visible attributes and safety properties match. Keep the current mode visible even if enumeration omits it.
- Do not label a mode as recommended or native without reliable evidence.
- Clicking the already selected mode is a no-op.
- Selectable modes must be usable for desktop GUI and must not be interlaced or stretched. Show the actual current mode even when it does not meet selection criteria. Preserve identifiers and relevant mode attributes when deciding equivalence.
- Only one preview can be active. Further switching is unavailable until Keep, Revert, or timeout.
- The confirmation window names the display and new resolution, displays remaining seconds, and offers Keep and Revert. Escape and closing the window revert. Expiry is measured against a deadline, so sleep or a delayed event loop does not grant an unlimited preview.
- On Keep, revalidate the topology and current selected mode. Never overwrite a user's external change during the preview. On Revert, restore only if the target still matches the preview mode and original display identity.
- These external-change checks are best effort: the public display API cannot atomically compare and change against another process. On ambiguous identity or a new connection generation, cancel rather than guess. Start a sleep-inclusive monotonic deadline after apply succeeds; check it before Keep and on wake. A save failure ends the preview through immediate guarded rollback, and rollback failure is reported separately.
- Quit is always available. Revert, Keep, save, and rollback failures have plain-language messages.

## Architecture

- A pure Swift model normalizes and sorts modes, distinguishes HiDPI/refresh variants, and produces display sections. This logic can be tested without changing hardware.
- A Core Graphics service enumerates displays and modes, reads display identities, performs configuration transactions, and observes reconfiguration. AppKit provides localized display names where available, with descriptive fallback names.
- Enumerate online topology for mirror detection, including mirror secondaries that may not be active. Use mirror-set membership as well as the secondary-to-primary relationship so the primary cannot accidentally remain selectable. Only active, non-mirrored displays are switching targets.
- A main-thread controller owns the menu, display refresh, preview state, monotonic deadline, and confirmation window. The switching policy is testable against a fake display service and injected clock.
- Track own transactions and compare topology snapshots after reconfiguration settles. Own mode-change callbacks do not count as external changes; a display identity, active set, mirror membership, or arrangement change does. A target mode changed by another app cancels confirmation. Refresh without re-entering configuration transactions from a callback.
- Register expected own transitions before calling Core Graphics, since callbacks may fire synchronously. Reconcile the resulting snapshot after the transaction returns. Allow the app's own expected mode and geometry changes while checking the rest of the topology.
- Read-only diagnostics provide a way to inspect real modes and topology without changing the user's display settings.

## Build and distribution

- Source repository includes a build script, meaningful tests, README, MIT license with an owner placeholder pending the user's preferred attribution, and GitHub Actions validation.
- Build a locally signed .app and ZIP for personal testing without paid membership. Put generated deliverables in outputs; keep scratch build files in work.
- Provide documented commands to build from source using Apple's Swift command line tools. Verify both arm64 and x86_64 compilation before claiming universal support; document the actual verified result.
- GitHub Releases can host the ZIP. An unnotarized download may require the recipient to approve it in Privacy & Security. Signing/notarization is an optional later distribution step requiring the user's Apple membership and credentials.
- Prepare a GitHub-ready source ZIP locally. Do not create a public repository, publish a release, or select a GitHub account without the user's explicit publishing instruction and destination.

## Verification and limits

- Automated tests cover mode normalization and ordering, identical display names, mirrored-group disabling, no displays, stale mode/display rejection, preview confirmation/timeout, disconnects, external changes during preview, and failed apply/commit/rollback.
- Compile the production app and validate its bundle, local signature, and packaging.
- Run read-only diagnostics against the attached displays and perform a menu/confirmation visual check if the available desktop surface supports it.
- Do not change the user's live resolution merely to test without an explicit instruction covering that test. Report which physical configurations remain untested, particularly multiple monitors and mirroring.
- Explicitly report app-only preview to permanent-save promotion and process-exit fallback as physically unverified until an actual hardware switching test covers them.

## Builder review

An independent builder reviewed this proposal. The API limitations, mirror detection, transaction callback ordering, guarded rollback, identity ambiguity, and timing defaults above incorporate that review. Nothing important remains undecided for a local first release. Copyright attribution and GitHub publishing destination can be settled before public release.

## Sources

- [Apple Quartz Display Services](https://developer.apple.com/documentation/coregraphics/quartz-display-services)
- [Configuration scopes](https://developer.apple.com/documentation/coregraphics/cgconfigureoption)
- [Display reconfiguration callbacks](https://developer.apple.com/documentation/coregraphics/cgdisplayreconfigurationcallback)
- [Mirror-group detection](https://developer.apple.com/documentation/coregraphics/cgdisplaymirrorsdisplay(_:))

## User-requested interface revision

The menu bar icon opens a native compact popover. Each active display has up to five visual text-size cards, ordered from Larger Text to More Space, with the selected choice outlined. Modes of the same logical size are grouped; HiDPI and the current refresh rate are preferred, while retaining the active size. A Default caption requires the public IOGraphicsTypes default flag. The complete resolution list is available only through All resolutions…. A long display list scrolls. The same tested Keep/Revert and display safety rules apply. The main interface does not expose refresh-rate variants as separate cards.

Review hardening: refuse previews without an enumerated restorable original; synchronously invalidate connection tokens on received remove/add callbacks using a lock; disable mutation if observation or reliable identity is unavailable; refuse ambiguous identities; recheck expiry after validation.
