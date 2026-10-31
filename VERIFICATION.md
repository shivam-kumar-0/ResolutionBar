# Verification — 2026-10-31

This is a first-release preview, not a claim of fully verified hardware compatibility.

## Passed locally

- 34 Swift Testing checks for mode normalization, current-mode preservation, mirrored-group blocking, names, scaling-preset reduction, system-default preservation, synchronous connection-token invalidation, preview/commit/rollback, expiry, disconnects, ambiguous identity, and failure recovery.
- New policies and review regressions were observed failing before implementation, then passing.
- Native Swift/AppKit executable compiled for arm64 and x86_64 with macOS 13 deployment target.
- Native menu and compact-picker construction for one display, multiple extended displays, a mirrored group, and no displays.
- Safe demo interaction: choosing a preset opens confirmation; Keep, Revert, and window close apply the expected in-memory result and dismiss confirmation. Escape is bound to Revert. No physical display modes changed during these checks.
- Compact picker rendered and visually inspected; up to five visual cards, selected outline, Default only for a reported default, Larger Text/More Space endpoints, and advanced list separated from the main picker.
- Universal bundle metadata, both architecture slices, ad-hoc code signature, ZIP, and checksum validated.
- Independent source review; important recovery findings corrected and covered by regressions. The subsequent user-requested preset interface received a focused review; default-mode preservation was corrected with a regression.

## Hardware and platform limits

- The command execution session reported no online displays through read-only Core Graphics diagnostics. This is an execution-session result, not proof that the user's GUI session has no displays.
- No real resolution change, physical disconnect/mirroring/lid-close/wake sequence, permanent-save promotion, or process-exit fallback was exercised.
- Intel and macOS 13 runtime behavior require testing on those systems. Compilation is verified; runtime equivalence is not assumed. An inactive CI template is prepared for Apple Silicon and Intel runners. GitHub rejected the original source push because its OAuth credential lacked `workflow` scope; the workflow is published as `docs/github/ci.yml.example` instead. Enable it using a credential permitted to manage workflows. GitHub CI has not run.
- Native picker rendering and demo confirmation behavior were checked locally. A desktop automation attempt could launch the bundle but could not capture its menu bar-only UI, so it is not claimed as end-to-end mouse/keyboard verification.
- A browser-downloaded ZIP remains unnotarized and can require Gatekeeper approval. No Developer ID credentials were used.

## Reproduce

```bash
bash scripts/test.sh
bash scripts/build-app.sh
dist/ResolutionBar.app/Contents/MacOS/ResolutionBar --smoke-test
dist/ResolutionBar.app/Contents/MacOS/ResolutionBar --demo multiple
```

The demo service never invokes the hardware display adapter. Test physical switching only when disruption to your desktop is acceptable, keeping an alternative means of recovery available.
