# Sway architecture

Sway is a menu-bar app in two layers: a pure-Swift core that holds every
decision, and a thin macOS layer that feeds it signals and shows its output.

```
           macOS signals                         SwayCore (pure, deterministic, tested)
┌──────────────────────────────┐        ┌──────────────────────────────────────────────┐
│ HID idle counter (IOKit)     │──5 s──▶│ ActivityTracker   active / away / asleep,    │
│ sleep / wake / lock events   │        │                   breaks, work stretches     │
│ mic + camera "in use" (CoreAudio,     │        │                  ▼                  │
│   CoreMediaIO), full-screen front app │ │ BreakScheduler    which breaks are owed     │
│ power source (IOKit)         │        │                  ▼                           │
├──────────────────────────────┤        │ InterventionEngine  dedupe, cooldowns,       │
│ AVFoundation capture         │        │   budgets, snooze limits, holds, back-off    │
│  640×480, ≤5 fps delivered,  │        │                  ▲                           │
│  1 frame / 2 s analysed      │─obs──▶ │ PostureEngine     smoothing, confidence,     │
│ Vision: face rect (rev 3) +  │        │   hysteresis, sustained episodes, stillness  │
│  body pose every 3rd frame   │        │ CalibrationBuilder  baseline + quality report│
└──────────────────────────────┘        │ Personalization   bounded, explained         │
                                        │ PatternDetector   level-4 "fix the setup"    │
                                        │ Ledger / SwayStore  daily JSON, retention    │
                                        └──────────────────────────────────────────────┘
                                                           │
                                   AppModel (MainActor coordinator, 5 s tick)
                                                           │
                    MenuBarExtra popover · Dashboard · Routine player · Calibration ·
                    Setup assistant · Settings · native notifications with actions
```

## Core (`Sources/SwayCore`)

Every type takes the current time as a parameter, so tests replay hours of
behaviour in milliseconds.

- **ActivityTracker**: one tick every 5 s with the system idle time. The
  user is *away* once idle passes the away threshold (default 2 min). The
  away period starts at the last input, and the time already credited after
  it is retracted. Returning closes the away period. It counts as a break
  (micro ≥ 2 min, long ≥ 5 min); a shorter absence is counted as work.
  Sleep/lock moves the tracker to *asleep*. A tick gap over 90 s (a missed
  sleep notification, a suspended process) is never credited as work.
  Guided breaks count only if the user really stepped away or stayed mostly
  idle; a guided break spent away counts once, from its start.
- **BreakScheduler**: derives due reminders from the tracker alone. A micro
  break yields to a long break due within 10 min. A long session (default
  120 min) escalates every 30 min. Eye rest is opt-in. Each due occurrence
  has an `instanceID` (e.g. `micro@<reference time>`), the key for
  dedupe and snoozing.
- **PostureReminders**: turns sustained episodes into posture reminders,
  and recurring issues into one workstation suggestion a day. A posture
  reminder stays in the menu bar while it's new, when a break falls due
  within 5 min either side (less with short break intervals), or when its
  issue is recurring (little movement excepted). An easing episode is
  `standby`: a notification already on screen stays until the episode
  really ends, and nothing new is sent. It also maps notification clicks
  to actions (`NotificationRouting`): the body does `ReminderKind.primaryAction`.
- **InterventionEngine**: turns due reminders into at most one notification
  per evaluation. `decide` is pure and returns, for every reminder, whether
  it was sent, held (and why) or waiting (`Blocker`, with a plain label);
  `evaluate` also records hold times and expires stale notifications:
  - holds: pause, notifications off, macOS not showing Sway's
    notifications, quiet hours, mic/camera in use elsewhere, a full-screen
    app in front;
  - a 3-min settling time after a hold that settles ends;
  - a notification on screen whose reminder is gone, replaced or back to
    menu-only is reported in `expired` and removed;
  - per-instance dedupe (never re-sent unless snoozed);
  - per-kind cooldowns, doubled per consecutive dismissal;
  - global spacing (8 min) and budgets (3/hour, 14/day);
  - a snooze limit (2 per reminder);
  - after 3 consecutive dismissals or "not helpful" marks, that kind goes
    menu-bar-only until the next local midnight. Long-session prompts are
    exempt from this and from budgets.

  Levels are `menu`, `notify` and `setup`. Everything held or blocked stays
  visible in the menu with its reason.
- **DecisionLog**: writes each change in a reminder's state once (sent,
  held, waiting and why, expired, no longer due, answered); at most 200
  entries, shown in Diagnostics.
- **PostureEngine**: works on observations relative to the calibration.
  - Per-issue values: head-down score (projection onto the user's own
    "look at the keyboard" movement, or face drop / 0.5 face heights),
    face-size ratio for leaning in, roll delta for tilt, and shoulder-line
    delta when shoulders are visible.
  - Values are smoothed by a time-aware EMA (τ = 8 s).
  - Unknown values: a frame with no face, more than one face, confidence
    under 0.6, an implausible face size, or a head turned more than 28° from
    calibration. Values are also unknown while fewer than 60% of the last
    2 minutes' frames were usable.
  - A `SustainedDetector` per issue turns values into episodes. The value
    must stay above *enter* for the minimum duration (5 min by default),
    with dips under 20 s ignored. The episode ends only after 20 s below
    *exit*, which is lower than *enter* (hysteresis). If no usable frames
    arrive for 45 s, an episode ends where it was last seen.
  - Stillness: head movement (std dev over 5 min) under a threshold for
    45 min.
  - A calibration from another camera produces nothing until the user
    recalibrates.
  - `FrequentPatternDetector` (per issue: head down, leaning in, little
    movement) keeps per-minute observed and over-the-line time for a
    rolling 60-min window. Only bouts of 30 s+ count; a 10 s dip doesn't end
    a bout and a 45 s gap in observation does. It flags an issue with 30+
    observed minutes and 4+ bouts covering 35%+ (little movement: 70%+, in
    2+ bouts). The app records a flag once a day (`Ledger.flagFrequent`),
    which feeds the workstation suggestion.
  - `CalibrationHealthMonitor` keeps 10-s slots of observed and "off"
    time (face centre more than 0.22 image widths from calibration, or size
    outside 0.6–1.8×). 85% off over 10 min (5+ observed) marks it suspect:
    status `calibrationSuspect`, no posture values. 30% or less over 3 min
    clears it. Off-geometry frames never yield posture values.
- **Personalization**: needs at least 4 prompts of a kind in 14 days. It can
  space break reminders out by up to 50%, make a posture issue up to 60% less
  sensitive, or double a posture cooldown. Every change carries an
  explanation shown in the dashboard. It never makes Sway more insistent.
- **PatternDetector**: an issue seen in 3+ episodes today, or on 3+ of the
  last 7 days, stops producing identical notifications. Sway suggests a
  workstation change once a day instead.
- **Store**: JSON in `~/Library/Application Support/Sway`:
  - `settings.json`
  - `calibration.json`
  - `state.json` (tracker and policy state, so a relaunch keeps timers)
  - `days/YYYY-MM-DD.json`

  Lists inside each daily record are capped at 300 entries. Day files older
  than the retention window (90 days by default) are pruned. Writes are
  atomic, and dates keep millisecond precision.

## App (`Sources/SwayApp`)

- **AppModel**: the single MainActor coordinator.
  - Every 5 s: tracker tick → context refresh (every 10 s) → camera
    on/off → camera time accounting → guided-break bookkeeping → schedule +
    posture candidates → policy → notification.
  - Saves every 60 s, on sleep, and on quit.
  - The camera runs only while monitoring is on, access is granted, a
    calibration exists for the selected camera, the user is active, coaching
    isn't paused and the Mac isn't asleep or locked. It stops as soon as any
    of these stops being true.
- **CameraService**: capture and Vision run on a private utility queue.
  - Frames arrive at the lowest rate the camera supports (≥ 5 fps), and
    only one per sample interval is analysed. The interval is 2 s by
    default, doubled on battery and multiplied by 2.5 while no face is found.
  - Pixel buffers are never retained or written. Calibration's live preview
    is drawn by `AVCaptureVideoPreviewLayer`; Sway's code never sees those
    pixels.
  - It recovers from runtime errors (3 retries with backoff) and from
    disconnects.
- **NotificationService**: `UNUserNotificationCenter` categories with actions
  (1-min routine, 3-min break, snooze, not helpful, recalibrate, done, check
  setup). An explicit dismissal counts as "dismissed". Notifications of one
  kind replace each other rather than stack. When Sway runs unbundled,
  reminders appear only in the menu.
- **Views**:
  - `MenuView`, the popover, answers five questions top to bottom: is
    monitoring on, does anything need attention, how long have I been
    working, when should I move, what can I do now.
  - `DashboardView`: Today, Trends (Swift Charts) and Insights.
  - `RoutinePlayerView` with `FigureView`, animated line drawings for each
    movement.
  - `CalibrationView`, `SetupAssistantView`, `SettingsView`, and
    `OnboardingView`.
- **Tooling** (never used in normal runs):
  - `--benchmark` measures the pipeline.
  - `--seed-demo-data` and `--snapshots` render every screen offscreen from
    demo data. They refuse to run without `SWAY_DATA_DIR`, and snapshots
    also require `SWAY_NO_CAMERA`.
  - `--render-icon` draws the app icon.

## Decisions

- **JSON files over SwiftData or SQLite**: a day is a few KB, and the data
  is small, append-mostly, human-inspectable and trivially deletable. It
  also keeps the core testable without a database. SwiftData would tie the
  model layer to the app target and macOS 14 persistence semantics, for no
  benefit at this size.
- **No ML, no LLM**: thresholds, hysteresis and bounded counting rules are
  transparent and testable, and adequate for a single user.
- **AppKit windows for everything except the popover**: SwiftUI `Window`
  scenes are unreliable to bring forward from an accessory (no-Dock) app.
- **No Focus/DND API**: macOS doesn't expose Focus state to ordinary apps,
  so Sway relies on macOS holding its notifications during Focus. Meeting
  and screen-share detection use only what macOS exposes, the mic or camera
  running in another process, and the UI says so.
- **Not sandboxed, hardened runtime on**: ad-hoc signed with the camera
  entitlement. Sandboxing would also work for these APIs. It's left off to
  keep local builds simple. It's a one-entitlement change for distribution.
