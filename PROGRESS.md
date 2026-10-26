# Sway: progress

Last updated: 2026-10-26.

## Status

All five phases are implemented, the app builds and runs, and 62 automated
tests pass. What still needs hardware, permissions or a person is listed
under "Not yet verified" and in [docs/VALIDATION.md](docs/VALIDATION.md).

## Completed

- [x] Phase 1: menu-bar app (no Dock icon, optional Dock icon), settings with
      validation and tolerant decoding, JSON persistence with retention and
      delete-all, launch at login (SMAppService), camera and notification
      permission handling, operation without camera, sleep/wake/lock
      handling, `.app` bundle (ad-hoc signed, hardened runtime, icon).
- [x] Phase 2: activity tracking from the HID idle counter, break detection,
      the break scheduler (micro, long, long-session escalation, opt-in eye
      rest), the notification policy (dedupe, cooldowns, spacing, budgets,
      snooze limits, holds for calls/full screen/pause/quiet hours, back-off
      after dismissals), native notifications with actions, guided breaks,
      and 12 guided routines with animated figures.
- [x] Phase 3: camera pipeline (AVFoundation, 640×480, low frame rate,
      adaptive sampling, off when away/paused/locked, disconnect and error
      recovery), Vision face (rev 3: pitch/yaw/roll) and upper-body pose,
      calibration flow with quality report and "look at the keyboard"
      reference, sustained-deviation detection with smoothing, confidence
      gating and hysteresis, stillness detection.
- [x] Phase 4: dashboard (Today / Trends / Insights), comfort check-in,
      interpretable metrics with definitions, bounded and explained
      personalization, level-4 pattern escalation, workstation setup
      assistant with manual measurements.
- [x] Phase 5: tests, benchmark mode, resource measurement, offscreen UI
      snapshots (reviewed in light and dark), fresh-eyes review, docs.

## Test results

`swift build --product sway-tests && .build/debug/sway-tests`, last run
2026-10-26: **62 passed, 0 failed, 258 checks, ~1.5 s.**

Covered: activity-session calculations; break scheduling; sleep/wake (two
hours of sleep, a missed sleep notification, sleep while away); midnight
splitting; guided breaks with no double counting; notification cooldowns,
dedupe, budgets, holds and snooze limits; repeated dismissals backing off;
long sessions escalating within budget; personalization bounds; settings
round trip and tolerant decoding; calibration persistence; runtime state
restore; signal smoothing; confidence and reliability gates; sustained
deviation (5 s lean → nothing; 8 min lean → one episode dated from its start);
frequent position changes; 45 min still; face tracking lost briefly vs. for
minutes; camera disconnect; camera switch requiring recalibration;
hysteresis; looking at another monitor; data retention and deletion.

Synthetic landmark sequences are deterministic (xorshift noise, fixed seed).

## Measured performance

Machine: MacBook Pro (MacBookPro18,1, M1 Pro, 10 cores), macOS 27.0.1. The
laptop was under heavy unrelated load during measurement (load average
20–70), so these are upper bounds.

`Sway --benchmark` (release build):

| Stage | Cost |
| --- | --- |
| Vision, face detection only (640×480 frame) | 7.0 ms per frame |
| Vision, face + upper-body pose | 16.2 ms per frame |
| Posture engine, per observation | 15.9 µs |
| Activity tick + scheduling + notification policy | 1.9 µs per tick |
| Process memory footprint (benchmark process) | 41 MB |

Running app, camera off, 5-minute measurement of the bundled release
binary: see "Idle run" below.

Estimated camera-on cost (derived, not measured live): 1 frame per 2 s, with
body pose on every third frame, is ≈ 10 ms of Vision work per 2 s, about
0.5% of one core, plus capture overhead at the camera's lowest frame rate.
Settings → Diagnostics shows the live numbers once the camera runs.

### Idle run
(filled in below)

## Not yet verified (needs hardware, permissions or interaction)

- Live camera capture, calibration and posture prompts on a real face.
  Implemented and covered with synthetic sequences; I did not turn on the
  camera.
- Notification permission prompt and action buttons (needs a person to
  click).
- Launch at login (needs a logout/login).
- Real sleep/wake and lock/unlock transitions (tested with simulated events).
- Mic/camera-in-use and full-screen holds with a real call.
- `Xcode/Sway.xcodeproj` building in Xcode (the Xcode license isn't accepted
  on this Mac, so `xcodebuild` can't run; the project file parses and all
  references resolve).

## Known issues and limitations

- macOS doesn't expose Focus, meeting or screen-sharing state to ordinary
  apps. Sway relies on macOS holding notifications during Focus and treats
  "another app uses the mic or camera" as a likely call. It can't tell a
  dictation session from a call, or detect screen sharing without a mic.
- Camera estimates are relative to one calibration. Moving the laptop,
  monitor or chair invalidates them until you recalibrate. Sway can't
  detect such a move automatically, except a camera change.
- Head pitch from Vision is used only when the "look at your keyboard"
  reference teaches its direction. Without it, head-down relies on vertical
  face position, which also changes if you slouch down in the chair.
- Uneven-shoulder detection needs both shoulders in frame, which most laptop
  cameras don't show.
- Ad-hoc signing: macOS may ask for camera permission again after each
  rebuild (the signature changes). A Developer ID signature fixes this.
- Tests run through a small custom runner because the Command Line Tools on
  this Mac ship no XCTest. They port directly to XCTest if wanted.

## Next actions

1. Run docs/VALIDATION.md on real hardware, especially the camera sections,
   and tune default thresholds from real Diagnostics readings.
2. Accept the Xcode license and verify `Xcode/Sway.xcodeproj` builds.
3. Consider Developer ID signing and notarization for distribution.
