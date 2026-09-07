# macOS compatibility and recipient acceptance

MonsterDeleter targets macOS 15 or later. `scripts/build-app.sh` produces one universal app with
arm64 and x86_64 slices. CI builds on macOS 26 with Xcode 26.5 / Swift 6.3, then runs the exact
archived app on native macOS 15 Apple silicon and Intel runners without rebuilding.

## Reproduce the gates

```sh
scripts/build-app.sh
swift test --no-parallel
scripts/lint.sh
scripts/test-packaging.sh
scripts/self-test.sh
scripts/package.sh
mkdir -p build/unpacked
ditto -x -k build/MonsterDeleter-0.4.0.zip build/unpacked
scripts/check-app.sh build/unpacked/MonsterDeleter.app
scripts/self-test.sh --prebuilt-app build/unpacked/MonsterDeleter.app
```

Use the archive name for the version in `Packaging/Info.plist`. `check-app.sh` rejects missing
bundles, thin executables, either slice's incorrect minimum OS, a mismatched plist minimum OS,
and invalid signatures. `test-packaging.sh` exercises missing and thin disposable fixtures.
The self-test confirms a scratch selection, checks Trash outcomes and six checkpoint references,
then verifies Esc leaves another selection untouched. Keep only one MonsterDeleter running.

Read every `skip:` line: Retina glyph comparisons and physical keyboard dispatch can be
unavailable. Checkpoint captures do not measure continuous frame pacing or prove native
permission dialogs. Native runner success does not certify a particular physical Mac's UI,
performance, permission behavior or installation route. Rosetta tests the Intel slice on the
host OS, not an Intel Mac running macOS 15.

## Recipient acceptance

A universal artifact and CI are necessary gates. They do not certify the recipient Mac.
Record the archive SHA-256 and source commit with every result below.

### Hands-on checks

Prerequisites: access to the test Mac and its owner, confirm model/CPU/RAM and actual macOS build, enough disk space for a test copy, an unlocked desktop, permission for any Accessibility/VoiceOver changes, and a recorded baseline of settings. Use one running MonsterDeleter only. Keep the user's current app and preferences recoverable; isolate first-run and corrupt-character fixtures in a test account or approved test environment. Do not alter the signed production bundle to simulate failures.

1. Transfer the identified package by the intended handover route, verify its hash and architecture, and open it normally through Finder. Record any Gatekeeper outcome. Verify menu bar icon and no Dock icon, all introduction steps, skip/restart, window height, Guide, Settings and keyboard navigation.
2. Use **Play Demo** in the menu bar (the home window says **Play a Demo**). It creates its own scratch file and asks for a crosshair point. Cancel at the question first; then repeat and confirm. The two response buttons both confirm.
3. In Finder create a uniquely named test folder containing only newly created disposable files and a disposable nested folder. Right-click one item and choose **Services > Feed to Monster**. Cancel while asking and verify all contents remain. Repeat, confirm, verify only the selected targets reach Trash and any individual failures are reported. Finder owns restoration; Put Back availability and exact-name restoration are not app acceptance gates. Never empty the user's Trash as test cleanup.
4. Repeat a confirmed and cancelled selection in Icon, List, Column and Gallery views, plus the desktop. Verify the exact selection/count and any file-access prompts. Use disposable fixtures to test partial Trash failures and verify a readable error, never permanent deletion.
5. Select Kaiju, Cat and UFO in Settings, play each, relaunch to verify the saved choice. In the isolated account verify fresh Kaiju. Test a known valid character zip with **Choose Zip…** and a drop onto Settings, then a harmless invalid archive and unavailable-character fixtures. Verify real-character recovery and the no-working-character case.
6. With consent, test icon aiming off, requested/denied, granted and revoked. Watch Settings and the introduction together in the same process. Verify real prompt focus before claiming an unanswered wait; also verify no-prompt recovery, Stop Asking, self-activation not ending the wait, and live grant/revocation. Do not reset the owner's TCC database. Restore the recorded preference/grant afterward.
7. For granted aiming, capture the visible icon centres and hits in all Finder views. Test spaced icons, screen edges, mixed resolvable/unresolvable items, and 20+ disposable targets. Confirm 19 drawn hits maximum but all files reach Trash. If a second display is available, include mixed scaling and targets across displays; otherwise record that coverage as missing.
8. Test sound off/on, Esc, focus return, click-through animation and full-screen/Space behavior. With consent, use VoiceOver to traverse and operate the introduction and permission recovery text; an accessibility-tree dump alone is insufficient. Restore VoiceOver and display settings.
9. Run the performance measurements below. Save source/artifact IDs, OS, screen geometry, results, exceptions and private evidence. File a concrete defect for failures instead of labelling the machine supported.

### Performance measurements

A universal executable selects one native slice; that removes the need for translation on each supported architecture, but does not guarantee identical performance. [Apple universal binaries](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary), [Apple porting guidance](https://developer.apple.com/documentation/apple-silicon/porting-your-macos-apps-to-apple-silicon)

Record release artifact hash, power source, thermal state, background load, display mode and cache condition. On the actual Mac, measure each real character with one target and with 20+ targets:

| Measurement | Method and report |
|---|---|
| First launch and character load | Monotonic timestamps around launch, readiness, selection/load and first visible response. Five isolated cold-cache samples and at least twenty warm samples; report every cold sample and warm median/p95, not a CPU multiplier. Preserve original cache; clear only the isolated fixture's cache. |
| Finder targeting | Existing resolved/total/time logs across each Finder view; report resolution success, fallback reason and latency distribution. Preserve the 150 ms resolver budget unless measured defects justify an approved change. |
| Animation | Observe complete shows and record continuous walk/fly motion; use Instruments animation/hitch tooling available on the target, or a compatible recorded frame analysis. Report dropped/stalled presentation intervals separately from intentional 8 fps sprite stepping and the ask pause. |
| CPU and memory | Sample app and WindowServer CPU, physical footprint/RSS separately, memory pressure and swap before/during/after twenty same-process shows and repeated character swaps. Report peaks and whether memory returns to a plateau; do not infer allocation sharing from image API names. |
| Packaging | Record executable and whole-app/archive byte sizes. Shared artwork means the app need not double in size, but only the actual artifact establishes the increase. |

Proposed quality acceptance: existing functional/timing checks pass; no reproducible input stall, stuck panel, progressive memory growth, new sustained memory pressure or visibly stalled walk/fly motion attributable to the app. Flag a continuous-motion stall lasting a whole 125 ms sprite slot for investigation, not as an existing measured result. First-load and warm-response latency remain explicit measured results for maintainer review; this plan does not invent a one-second Intel guarantee. Set any additional numerical responsiveness budget from those measurements before declaring performance acceptance.

Log `NSScreen.frame` in points, actual window/view backing conversion and the selected display mode; do not infer backing dimensions from native panel dimensions. Continue using the existing point-coordinate conversion for Finder aiming. [Apple backing-scale guidance](https://developer.apple.com/documentation/appkit/nsscreen/backingscalefactor)

If performance fails, profile the failing case first. Reducing hit count, changing transparent overlays or downscaling accepted art changes the product and requires review; none is a preapproved compatibility shortcut.

For public release installation, never strip quarantine or disable Gatekeeper.
Exact-artifact publication gates and retry rules live in [releasing](releasing.md).
