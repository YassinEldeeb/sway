# Sway: progress

Last updated: 2026-10-26.

## Status

All five phases are implemented, followed by a reliability pass for daily
use (see "Reliability pass"). The app builds and runs, and 113 automated
tests pass. Two fresh-eyes reviews found defects; all clear ones are fixed.
What still needs hardware, permissions or a person is listed under "Not
yet verified" and in [docs/VALIDATION.md](docs/VALIDATION.md).

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
      personalization, pattern escalation, workstation setup assistant with
      manual measurements.
- [x] Reliability pass (2026-10-26): notification defects, frequent-pattern
      detection, notification decision log, calibration health, comfort
      check-in by area, a diagram for every setup item, clearer states in
      the menu bar.
- [x] Phase 5: tests, benchmark mode, resource measurement, offscreen UI
      snapshots (reviewed in light and dark), fresh-eyes review, docs.

## Test results

`swift build --product sway-tests && .build/debug/sway-tests`, last run
2026-10-26: **113 passed, 0 failed, 469 checks, ~5 s.** Also passes with
`TZ` set to Pacific/Kiritimati, Pacific/Honolulu and America/Los_Angeles
(the runner pins its own zone to UTC; DST tests set Europe/Lisbon).

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

Added in the reliability pass: notification click routing and setup-item
links; stale notifications removed (posture eased, break taken, replaced,
menu-only); a brief glance keeps a notification; settling after a call
with exactly one reminder after; macOS notifications blocked; blocker
explanations; silence lasting today only (also on DST days); long
sessions ignoring budgets; posture/break coordination (including ignored
breaks and 5-min intervals); the decision log; relaunch round trip; old
and partly unreadable saved files; repeated short leans and head-down
bouts; ordinary movement, low confidence and interruptions never flagged;
one long still stretch not a pattern; slow sampling; window clipping; moved
camera vs. ordinary posture; hedged numbers in setup guidance; legacy
keyboard-and-mouse answers.

Mutation checks: the settle time, expiry, decision log, minimum bout,
off-geometry gating, ignored-break yield, still-stretch rule, window
clipping, slow sampling, lenient decoding and DST end of day were each
broken on purpose; the matching tests failed.

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

This run used the bundled release binary with demo data, the camera off, the
menu-bar item live and the 5 s tick running. It was measured with `ps` CPU
time and `footprint` over 300 s, on 2026-10-26:

- First build: **0.127% of one core** on average (0.38 s of CPU in 300 s),
  21 MB physical footprint.
- After the review fixes (App Nap opt-out, a lock and display check every
  tick): **0.157% of one core** (0.47 s in 300 s), **20 MB footprint**.
- Resident size stayed at 69–79 MB, sampled every 30 s, with no growth, in
  both runs.

## Review fixes

An independent reviewer audited the code and found 16 defects. It
reproduced 8 of them with probes against the code; the other 8 came from
reading. All are fixed. The 9 regression tests are in
`Sources/SwayTests/RegressionTests.swift`. The tests that compile against the
old API were run on the pre-fix commit, and 3 of 4 failed there. The 4th was
then strengthened; on the old code it should score 0.63 against a 0.55
threshold (calculated, not re-run).

- **Data loss:** on the first event of a new day, yesterday's file was
  overwritten with a nearly empty record. The ledger now loads a day from
  disk before updating it.
- **Guided breaks:**
  - A guided break left over from a relaunch could retract hours of work.
    Guided breaks now carry a planned end, stale ones are ignored, and a
    relaunch cancels one.
  - A guided break taken at the desk counted as both work and break.
- **Late timers:** a late tick (App Nap) while typing counted as a break.
  Sway now opts out of App Nap and measures real sleep from the gap between
  the continuous and absolute clocks.
- **Long-session prompts:** after three dismissals they got more frequent.
  They now keep their backoff.
- **Menu-bar card:** Dismiss and Snooze didn't hide it, and repeated clicks
  silenced the reminder kind. Responses are now tracked per reminder: they
  hide the card and count once.
- **Camera:**
  - Posture state could freeze on stale data, and a start/stop race could
    leave the camera reported as on while dead. A watchdog now catches
    stalled frames, and stale starts are dropped by generation.
  - Error recovery could restart a camera that had been stopped.
  - The frame-rate setting could raise an exception on cameras with
    fractional rates. It now uses durations from the supported range, set
    after configuration.
  - A camera-permission answer after the calibration window closed could
    start the camera with no window open.
  - A camera-queue data race and a main-thread `queue.sync`.
  - Sway's own camera could count as "another app's camera" and hold all
    notifications.
- **Suspension:** sleep, display, lock and session states shared one flag,
  so a key press at the lock screen restarted tracking and the camera.
  Each reason is now tracked separately and checked against the live
  session state on every tick.
- **Head-down detection:** a tiny or upward "look at your keyboard"
  reference made it hypersensitive or inverted. The reference now has to be
  a clear downward move, and the score is floored.
- **Dashboard:** it read up to 30 day files on every render. Past days are
  now cached, and Vision stats are published once per tick.
- **Clock changes:** a backwards clock step credited time twice.

## Reliability pass: checked on the real app (2026-10-26)

- Upgrade over a day of the owner's real data: session start, active time
  (3992 → 4081 s) and camera time (3190 → 3245 s) carried over.
- Camera permission kept across reinstalls; after a relaunch the camera
  resumed with the same calibration file (identical hash) and camera time
  kept growing.
- Camera on, live: 5–15% of one core (median about 7%, 2-s frames, laptop
  load about 45 from other work), 90–115 MB resident, 138 MB footprint
  (peak 156 MB). That's higher than the derived ~0.5% estimate above, which
  should be read as wrong for this machine under load.
- Launch at login: `Sway --login-item cycle` registered the app
  ("enabled") and restored it to off. Starting at an actual login was not
  tested.
- On this Mac, macOS has never shown Sway's notifications (Sway isn't in
  System Settings → Notifications), so earlier "sent" reminders were
  invisible. The app now says so in the menu and the decision log.

## Not yet verified (needs hardware, permissions or interaction)

- A full held-lean episode on a real face through to a visible
  notification, and the frequent-bout and moved-camera states on a real
  face (all covered with synthetic sequences only).
- Notification permission prompt, body clicks and action buttons (needs a
  person to click).
- Launch at login across a real logout/login.
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
- Camera estimates are relative to one calibration. A large lasting move
  of the laptop, monitor or chair is caught (posture warnings stop, the menu
  offers to recalibrate); a small one (a few cm, a changed lid angle) still
  shifts the estimates without warning. Sitting far back for 10+ minutes
  can also look like a moved setup.
- Comfort check-ins recorded before the back was split into upper and lower
  stay as "back" and aren't part of the per-area averages.
- Head pitch from Vision is used only when the "look at your keyboard"
  reference teaches its direction. Without it, head-down relies on vertical
  face position, which also changes if you slouch down in the chair.
- Uneven-shoulder detection needs both shoulders in frame, which most laptop
  cameras don't show.
- Ad-hoc signing: `build-app.sh` now signs with the bundle id as the
  designated requirement, so a rebuild keeps the camera permission (seen
  once on 2026-10-26: the camera ran again right after a reinstall). If macOS still resets it, Sway asks
  again at launch instead of staying silently off. A Developer ID signature
  is the proper fix for distribution.
- Tests run through a small custom runner because the Command Line Tools on
  this Mac ship no XCTest. They port directly to XCTest if wanted.

## Next actions

1. Run docs/VALIDATION.md on real hardware, especially the camera sections,
   and tune default thresholds from real Diagnostics readings.
2. Accept the Xcode license and verify `Xcode/Sway.xcodeproj` builds.
3. Consider Developer ID signing and notarization for distribution.
