# Sway: review brief

For a reviewer who hasn't seen the project. It covers what the app does for
the user, how each part works, the defaults, what has been verified, and
where we'd like you to push. Repository: `~/development/sway`, branch
`master` (2026-10-26; updated after the reliability pass, §6). Paths below
are relative to it.

## 1. What Sway is

Sway is a native macOS menu-bar app (Swift 5.10, SwiftUI plus AppKit, macOS 14+)
for people who spend long days at a computer. It does three things:

- It notices long stretches of work without a break, using only the system
  idle counter, and suggests a break or a short guided routine.
- Optionally, with the camera, it notices *sustained* head and upper-body
  positions relative to the user's own calibration (head tilted down,
  leaning toward the screen, head tilted to one side, one shoulder raised,
  and very little movement) and suggests a change.
- It helps the user set up the workstation (screen, chair, desk) with a
  checklist and entered measurements.

Design principles:

- Movement and variety over one "correct" posture.
- React to positions held for minutes, never to brief ones.
- Interrupt rarely, give one concrete suggestion, and back off when ignored.
- Everything stays on the Mac. No network, account or analytics.
- No medical claims. Camera numbers are relative estimates, not spine
  measurements, and the UI says so.

Size: about 7,500 lines of Swift. The pure core (`Sources/SwayCore`, about
2,350 lines) holds every decision and is deterministic. The app layer
(`Sources/SwayApp`) feeds it signals and shows its output. The tests are in
`Sources/SwayTests`.

## 2. The user's journey

1. **First launch: onboarding.**
   - A welcome screen with a "not a medical device" note.
   - A request to allow notifications. It explains the limit (at most 3 an
     hour) and the one-click actions.
   - An optional offer to set up posture monitoring with the camera.
   - Both can be done later from the menu bar.
2. **Calibration** (only if the camera is wanted, about 15 s).
   - The user picks a camera and sits in a comfortable working position.
     Sway captures a baseline: face position, size, pitch, yaw and roll, plus
     shoulders if visible.
   - Optionally, the user looks at the keyboard for a few seconds. This
     teaches Sway what "head down" looks like for this person.
   - A review screen shows quality (usable or not), what can be measured
     with this camera (e.g. "shoulders not visible, so uneven-shoulder
     detection is off") and placement warnings.
   - Frames are analysed in memory and never saved.
3. **Day to day:** Sway lives in the menu bar.
   - The icon changes when something needs attention.
   - A camera mark shows whenever the camera is on.
   - An optional work timer can sit next to the icon.
   - Reminders arrive as native notifications at most a few times an hour.
   - Clicking an action starts a routine or a break.
   - The dashboard shows the day and trends.
4. **When something keeps recurring** (the same posture issue 3+ times a
   day, on 3+ of the last 7 days, or often in short bouts), Sway stops
   repeating it. It suggests fixing the setup once that day, and the setup
   assistant opens at the matching item from that suggestion.

## 3. Features in detail

### 3.1 Menu bar popover

From top to bottom:

- **Whether coaching is on**, with pause options: 30 min, 1 h, 2 h, or
  until tomorrow.
- **What needs attention now.** Each item has one-click actions: start a
  routine, take a break, snooze, dismiss. Reminders that were held back
  (for example during a call) still appear here.
- **Time worked** in the current stretch.
- **A countdown** to the next break.
- **Posture status line.** Examples: "Tracking", "Leaning toward the screen
  · counts in 3:20" (a deviation being timed), "Waiting for camera
  permission", "Camera off while you're away". It has an on/off switch, or
  a Calibrate button when no calibration exists.
- **A list of routines** to start at any time.

### 3.2 Activity and breaks (no camera needed)

- **How activity is measured.** Every 5 s Sway reads the system HID idle
  time (IOKit). It never sees keystrokes, apps, windows, the clipboard or
  browsing.
- **When the user counts as away.** After 2 min idle. The away period is
  dated from the last input, and the time already credited after it is
  taken back. An absence of 2+ min is a short break and 5+ min is a long
  break. A shorter absence counts as work, so a few seconds of reading
  never resets the timers.
- **Sleep and lock** count as away time. If a tick arrives more than 90 s
  late (a missed sleep notification, a suspended process), the gap is never
  credited as work. Real sleep is measured from the gap between the
  continuous and absolute clocks. Sway opts out of App Nap so late timers
  don't look like breaks.
- **What gets reminded:**
  - a movement break every 25 min of work;
  - a longer break every 55 min;
  - a "long session" reminder after 120 min without a real break, repeating
    every 30 min;
  - eye rest every 20 min (20-20-20), opt-in and off by default.
  - A movement break yields to a longer break that is due within 10 min.
    Eye rest yields to any movement reminder that is due soon.
- **Guided breaks.** "Take a 3-min break" starts a timer. It counts as a
  break only if the user stepped away or stayed mostly idle during it. A
  completed routine also counts as a movement break, if it lasted at least
  30 s or so (a 10 s one doesn't count).
- **Midnight.** Time is split between the two days.

### 3.3 Notifications: when, what, and what stops them

This is the part users notice most. Everything below uses the default
settings. Sources: `BreakScheduler.swift` (when a break is due and its
text), `PostureReminders.swift` (posture and workstation reminders, click
routing), `InterventionEngine.swift` (whether it may be sent, and why
not), `DecisionLog.swift`, `NotificationService.swift` (buttons).

#### Every notification Sway can send

Times are counted from the last real break, meaning time away of 2+ min or
a completed routine or guided break.

Clicking the notification itself does the reminder's main action, the
same as the first button in the menu-bar card: a routine for posture and
eye reminders and the movement break, a guided 3-min break for the longer
break and the long session, and the setup assistant (opened at the matching
item) for a workstation suggestion.

| Reminder | When it is due | Title and text (exact) | Buttons | Click on the notification |
| --- | --- | --- | --- | --- |
| **Movement break** | 25 min of work. Not sent if a longer break is due within 10 min. | "Quick movement break" / "25 min since you last moved away. Stand up, roll your shoulders, or try a 1-minute routine." | Start 1-min routine · Take a 3-min break · Snooze 10 min · Not helpful | Opens "Desk mobility minute" |
| **Longer break** | 55 min of work. | "Time for a longer break" / "You've been working continuously for 55 min. A short walk could help." | same as above | Starts a guided 3-min break |
| **Long session** | 120 min without a long break, then every 30 min. Replaces the longer-break reminder. | "You've been at it for 2 h" / "That's an unusually long stretch without a real break. A few minutes away from the desk — a short walk, water, daylight — is a good reset." | same as above | Starts a guided 3-min break |
| **Eye rest** (opt-in, off by default) | 20 min since the last eye rest or break. Skipped if a movement reminder is due within 3 min. | "Rest your eyes" / "Look at something about 6 metres (20 feet) away for 20 seconds, and blink a few times." | Done · Snooze 10 min · Not helpful | Opens "20-20-20 eye rest" |
| **Head tilted down** (camera) | Held 5 min, then 3 more min (8 min in all). | "Your head has been tilted downward for a while" / "About 8 min. Try changing position: sit back and bring your gaze up. If this happens a lot, the screen may be too low." | Start 1-min routine · Snooze 10 min · Recalibrate · Not helpful | Opens "Gentle neck mobility" |
| **Leaning toward the screen** (camera) | Held 5 + 3 min. | "You've been leaning toward the screen" / "About 8 min. Sit back against your chair; if text is hard to read, enlarge it (⌘+) instead of moving closer." | same as head down | Opens "Gentle neck mobility" |
| **Head tilted to one side** (camera) | Held 5 + 3 min. | "Your head has been tilted to one side" / "About 8 min. Re-centre your head, and check whether what you're looking at sits off to one side." | same | Opens "Gentle neck mobility" |
| **One shoulder raised** (camera, only if both shoulders are visible) | Held 10 + 3 min. | "One shoulder has been raised for a while" / "About 13 min. Let both shoulders drop. Check the mouse isn't too far out or too high." | same | Opens "Shoulder release" |
| **Little movement** (camera) | Head barely moved for 45 min, then 3 more min. | "Your neck position has stayed very still" / "About 48 min with little movement. Try a comfortable movement break — roll your shoulders, look around, or stand for a minute." | same | Opens "Desk mobility minute" |
| **Workstation suggestion** | A posture issue keeps coming back: counted 3+ times today, on 3+ of the last 7 days, or seen often in short bouts (below). At most once a day per issue. | "<Issue> keeps coming back", e.g. "Leaning toward the screen keeps coming back" / issue-specific setup advice, e.g. "You keep leaning toward the screen. Text size, screen distance or glasses can be the cause: try a larger font or moving the screen a little closer rather than bringing yourself to it." | Check my setup · Not helpful | Opens the setup assistant at the matching item: head down → monitor height, leaning → viewing distance, head tilt → external monitors, shoulder → forearm support, little movement → varying position |

The durations in the texts ("25 min", "About 8 min") are filled in live.
There are three levels (`InterventionLevel`): **menu** (the menu bar only),
**notify** (a notification with buttons) and **setup** (the workstation
suggestion). The earlier four-level model ("gentle" vs "actionable") had no
visible difference and was removed.

What the buttons do:

- **Start 1-min routine** opens the routine that fits the reminder (last
  column above). It counts as "acted on".
- **Take a 3-min break** starts a guided break. The popover shows a break
  card with a countdown, and other notifications are cleared. The break
  counts only if the user stepped away or stayed mostly idle.
- **Snooze 10 min** brings the same reminder back after 10 min, still
  subject to spacing and budgets. After 2 snoozes the reminder comes back
  without a Snooze button.
- **Recalibrate** opens calibration.
- **Done** (eye rest) resets the eye-rest timer.
- **Check my setup** opens the setup assistant at the matching item.
- **Not helpful** counts double toward back-off (below).
- **Closing the notification** with its close control counts as a
  dismissal. A notification that simply times out of view counts as
  nothing.

Buttons and clicks work after a relaunch: the notification delegate is set
before launch finishes, and responses are matched by the reminder's id and
kind, not by in-memory state.

#### A notification never outlives its reason

A posted notification is removed from Notification Center as soon as its
reminder is no longer current:

- the user took the break, or sat back (a posture episode that is easing
  ends its reminder at once);
- a newer occurrence of the same kind replaced it;
- the reminder dropped back to the menu bar only (for example, the issue
  became a workstation suggestion).

#### What happens before something becomes a notification

Each reminder starts as a menu bar item. It becomes a notification only if
every check passes, in this order:

1. **Not held.** Notifications are held while:
   - coaching is paused (30 min, 1 h, 2 h, or until tomorrow);
   - notifications are turned off in Sway;
   - macOS isn't showing Sway's notifications (permission not given, the
     alert style set to None, or turned off in System Settings). The popover
     says so and offers an "Allow" button; nothing counts as sent;
   - it's quiet hours (opt-in, 22:00–07:00 by default);
   - another app is using the mic or camera (a likely call);
   - a full-screen app is in front.

   macOS Focus also holds them, on the system side. While held, the popover
   shows the reminder with a "bell off" line saying why.
2. **Not already sent.** Each occurrence (e.g. "the movement break for this
   work stretch") is sent once. If ignored, it stays in the menu bar. It
   isn't re-sent; the next reminder is the next one due, such as the longer
   break at 55 min.
3. **Not silenced for today** (back-off, below).
4. **Settled after a hold.** When a call, full-screen app, pause or quiet
   hours ends, Sway waits 3 min, then sends at most the one most important
   reminder that is still current. Reminders that ended during the hold
   (a break taken, a position changed) are never sent late, so there is no
   burst after a meeting.
5. **Past its cooldown** since the last notification of the same kind:
   - movement break and eye rest: 15 min;
   - longer break and long session: 20 min;
   - each posture issue: 25 min;
   - workstation suggestion: 20 h.

   Each consecutive dismissal doubles the cooldown, up to 4×.
   Personalization can lengthen it further.
6. **At least 8 min since any Sway notification.**
7. **Within budget:** at most 3 in the last hour and 14 today. Long-session
   reminders are exempt from budgets.

If several reminders pass at once, the most important one is sent:

1. long session (100);
2. longer break (80);
3. posture (60);
4. movement break (50);
5. workstation suggestion (30);
6. eye rest (20).

The others wait in the menu bar, each with a line saying why ("Another
reminder went out recently; next possible at 10:42", "Hourly limit reached;
next possible at 11:05", "A more important reminder went out first").

**Posture and breaks together.** A posture reminder stays in the menu bar
from 5 min before a break is due until 5 min after it fell due, with the
note "A break is due soon and covers this." Outside that window posture
reminders go out as usual, even while an ignored break is still pending.

**Back-off.** Dismissing a kind 3 times in a row, or marking it "Not
helpful" twice (each counts 2), stops notifications of that kind for the
rest of the day only; the count starts over the next day. It still shows
in the menu bar. Acting on a reminder resets the count. Long-session
reminders are never silenced this way; they keep their growing cooldown
instead.

**Posture reminders once an issue is a pattern.** Once an issue keeps
coming back, Sway stops sending its normal reminder. That issue stays in
the menu bar with the note "This keeps coming back today, so Sway suggests
a setup change instead of repeating it.", and the workstation suggestion
is sent instead, at most once that day.

**Frequent short bouts** (`FrequentPatterns.swift`). Over a rolling
60-min window, with at least 30 min of reliable camera time in it:

- head down or leaning in: 4+ separate bouts over the line, each at least
  30 s, adding up to 35%+ of the observed time;
- little movement: 70%+ of the observed time very still.

Shorter glances and shifts are ordinary movement and never count. Time
with no face, low confidence or the camera off counts as neither "over" nor
"observed". A flag is recorded once a day per issue and leads only to the
workstation suggestion, never a notification per bout. The limits are in
settings (`frequentPatterns`) and clamped to safe ranges.

**Decision log.** Every change in a reminder's state (sent, held and why,
waiting and why, expired, no longer due) is written once to a log of the
last 200 entries, shown newest first under Settings → Diagnostics.

#### What the user sees without any notification

- **Menu bar icon:** the figure changes when a break or posture reminder is
  due. A camera mark shows whenever the camera is on.
- **Popover:**
  - an attention card for the most important current reminder, with its
    main action first and a line saying whether it was sent, is waiting
    (and why), or is held;
  - a "bell off" line when notifications are held, with the reason;
  - the posture line, which names the state: tracking, "Leaning toward the
    screen · counts in 3:20" while a deviation is being timed, camera off
    or unavailable, waiting for permission, needs calibration, away,
    paused, low confidence, looking at another screen, or "Calibration may
    be out of date" with a Recalibrate button.

#### A worked example (defaults, camera on)

09:00 start working. 09:25 "Quick movement break" (1st this hour). The user
ignores it, and it stays in the menu.

09:30 the user leans in. At 09:35 the lean counts, and the menu bar icon
changes. At 09:38 the posture notification is allowed:

- the movement break fell due 13 min ago, so posture no longer gives way
  to it;
- 13 min since the last notification, so 8-min spacing passes;
- 2nd notification this hour, within budget.

So "You've been leaning toward the screen" arrives at 09:38. If the user
sits back at 09:40, the notification is removed.

09:55 "Time for a longer break" (3rd this hour). Any other reminder before
10:25 waits in the menu, with the reason and the time it could go out.

**Reminders never start a routine by themselves.** A routine opens only
when the user clicks: a button, the notification itself, a menu item, or
the dashboard. This is deliberate, to avoid covering the user's work
mid-task.

### 3.4 Guided routines

There are 12 routines (`Sources/SwayCore/Content.swift`):

- **30 s:** neck reset, shoulder release, 20-20-20 eye rest.
- **1 min:** desk mobility minute, upper back opener, wrists and forearms,
  gentle neck mobility, eye relax, stand and reset.
- **3 min:** full reset, walk break.
- **5 min:** movement snack.

Each routine has:

- animated line-figure drawings per movement (`FigureView.swift`);
- a countdown and repetitions;
- skip and pause;
- safety notes with a stop rule (stop for pain, numbness, tingling or
  dizziness);
- "Did that help?" feedback at the end.

A notification's "Start 1-min routine" picks the routine that fits the
reminder. For example, a head-down reminder opens a neck routine.

### 3.5 Camera posture monitoring (optional, experimental)

**When the camera is on.** Only when all of these are true:

- monitoring is on and camera access is granted;
- a calibration exists for the selected camera;
- the user is active;
- coaching isn't paused;
- the Mac isn't asleep or locked.

It turns off when any of these stops being true, for example two minutes
after the user steps away.

**What happens every 2 s** (doubled on battery, 2.5× while no face is
found):

1. One frame (640×480) goes to Vision face detection. Body pose for the
   shoulders runs on every third frame. The frame is then discarded.
2. Measurements are compared with the calibration:
   - **Head down:** a score projected onto the user's own "look at the
     keyboard" movement. Without that reference, it uses face drop divided
     by 0.5 face heights.
   - **Leaning in:** face size relative to calibration. +16% counts, which
     is roughly 8–10 cm closer at a normal distance.
   - **Head tilt:** roll change in degrees. 12° counts.
   - **Uneven shoulders:** shoulder-line change in degrees. 7° counts, and
     only when both shoulders are visible.
   - **Little movement:** head movement (std dev over 5 min) under 0.06
     face heights.
3. Values are smoothed (time-aware EMA, τ = 8 s).
4. **Frames with no usable value.** A frame gives no value when there is no
   face, more than one face, face confidence under 0.6, an implausible face
   size, or a head turned more than 28° from calibration (looking at
   another screen). Below 60% usable frames in the last 2 minutes, Sway
   reports low confidence and warns about nothing.
5. **Calibration health.** If, for 10 minutes (with at least 5 observed),
   85% of the time the face sits far from where it was calibrated (centre
   more than 0.22 image widths to the side, or a size under 0.6× or over
   1.8×), Sway marks the calibration "may be out of date": posture warnings
   stop, the menu says why, and a Recalibrate button appears. Such frames
   never produce posture values, so a moved camera can't raise a lean
   warning first. It clears by itself after 3 min of 30% or less, or on
   recalibration. Leaning and sitting back stay well inside these limits.
6. **Timing.** A value over its line starts a clock.
   - It must stay over the line for 5 min: 10 min for shoulders, 45 min
     for little movement. Dips under 20 s are ignored.
   - Once counted, it ends only after 20 s below a lower exit line
     (hysteresis), or after 45 s without usable frames. In that case it
     ends where it was last seen.

**What the user sees for a held lean, with the defaults:**

| Time from leaning in | What happens |
| --- | --- |
| 0:00 | Diagnostics shows "+29% face size · over 16%, counts in 5:00". The menu shows "Leaning toward the screen · counts in 5:00". The dashboard shows "now · counts in 5:00". |
| 0:00–5:00 | Countdown. Sitting back for more than ~20 s resets it. |
| 5:00 | Counted. The menu bar icon changes and the popover shows the issue with actions and "A notification follows at <time> if this continues." The dashboard bar grows live. |
| 8:00 | A notification such as "You've been leaning toward the screen", with a concrete tip ("Sit back… enlarge text with ⌘+ instead of moving closer"). Subject to holds, budgets, and a break falling due within 5 min. |
| Sitting back | The reminder leaves the menu and any notification is removed at once. After 20 s the episode ends and is saved to the day with its duration. |
| 3rd episode of an issue today | Further notifications for it stop. A once-a-day "Leaning toward the screen keeps coming back" suggests a setup change. |

**Calibration rules:**

- A calibration belongs to one camera. With a different camera, Sway asks
  for recalibration and estimates nothing.
- A tiny or upward "look at the keyboard" movement is rejected. Sway then
  uses a cautious default and says so.

### 3.6 Workstation setup assistant

The assistant has 12 checklist items, each with a diagram (a "common
mistake" panel and one or two "recommended" panels with captions),
guidance, an evidence label and a quick check ("Yes, it's set", "Not yet",
"Doesn't apply"). Ranges are written as approximate ("about", "roughly",
"for most people"), and a test checks that every item stating degrees or
centimetres hedges them.

| Area | Items |
| --- | --- |
| Screen | Monitor height, viewing distance, screen angle and glare, external monitor |
| Chair | Chair height, foot support |
| Desk | Desk height, keyboard placement, mouse placement, forearm support |
| You | Neck and shoulders, varying position |

There is also a measurements page:

- The user enters eye-to-screen distance, where the top of the screen sits
  relative to their eyes, and whether they work on a laptop only.
- Sway turns these into suggestions. It never estimates them from the
  camera.
- The page lists its sources: OSHA, CCOHS, ANSI/HFES 100 and ISO 9241-5.

A calibration status row is included.

Answers saved under the old combined "keyboard and mouse" item still count
for both new items, and move to them on the next answer.

### 3.7 Dashboard

The dashboard has three tabs.

**Today:**
- active time, longest stretch, breaks, typical stretch, camera time;
- sustained posture deviations by type, including the episode happening
  now;
- prompts and how the user responded;
- an optional 0–10 comfort check-in for neck, upper back, lower back and
  eyes; each area can be left unanswered, and a note suggests seeing a
  clinician at 7 or above (Settings → General turns it off);
- a timeline.

**Trends:** 7, 14 or 30 days of the same measures, drawn with Swift Charts.

**Insights:**
- what personalization changed and why;
- recurring patterns;
- comfort over time per area, with days of workstation changes and
  recalibration marked on the chart, shown without claiming cause and
  effect;
- which issues came up often in short bouts, and what that means.

Every metric has a plain definition, and there is no posture score.

### 3.8 Personalization (`Personalization.swift`)

- **When it acts.** Only after at least 4 prompts of a kind in 14 days.
- **What it can change:**
  - space break reminders out by up to 50%;
  - make a posture issue up to 60% less sensitive;
  - double a posture cooldown.
- **Limits.** It never makes Sway more insistent. Each change has an
  explanation on the dashboard, and the user can reset all of it.

### 3.9 Settings

Settings has six tabs: General, Breaks, Notifications, Posture, Privacy and
Diagnostics.

**Posture tab:**
- each issue can be turned on or off;
- each has a sensitivity and a "must last N min" (1–30);
- "Notify after an issue lasts N more min" (0–20).

**Diagnostics tab (live):**
- CPU, memory, camera state, camera permission, frames analysed, Vision
  time per frame, tracking status and reliability;
- each posture reading and where it stands: under the line, over it with a
  countdown, or counted since a time;
- idle time, mic or camera in use elsewhere, full-screen app, battery.

### 3.10 Privacy and data

- **No network code.** Nothing leaves the Mac.
- **Camera frames** are analysed in memory and discarded, never recorded.
  The calibration preview is drawn by the system layer, so Sway's code
  never sees those pixels.
- **Data** is stored in `~/Library/Application Support/Sway`:
  - `settings.json`;
  - `calibration.json`, which holds numbers only;
  - `state.json`, holding timers and policy state so a relaunch keeps
    them;
  - `days/YYYY-MM-DD.json`, holding times and counts only.
- **Retention.** 90 days by default. One button deletes all data.

## 4. How it's built (pointers)

Full detail is in `docs/ARCHITECTURE.md`.

| Where | What it does |
| --- | --- |
| `SwayCore/ActivityTracker.swift` | Active, away and asleep states; breaks and stretches. |
| `SwayCore/BreakScheduler.swift` | Which reminders are due. |
| `SwayCore/InterventionEngine.swift` | Notification policy. |
| `SwayCore/PostureSignals.swift` | Smoother, `SustainedDetector`, motion window. |
| `SwayCore/PostureEngine.swift` | Per-issue values, gating, episodes, the "building" (being timed) state. |
| `SwayCore/Calibration.swift` | Baseline, look-down reference, quality report. |
| `SwayCore/Personalization.swift` | Bounded adjustments to timing and sensitivity. |
| `SwayCore/Store.swift` | Daily records and JSON persistence. |
| `SwayApp/AppModel.swift` | MainActor coordinator: the 5 s tick, camera on/off, reminder candidates, notifications. |
| `SwayApp/CameraService.swift` | AVFoundation and Vision on a private queue, stall watchdog, recovery. |
| `SwayApp/SystemSignals.swift` | Idle time, mic/camera in use, full screen, power, sleep clock. |

Why it's built this way:

- JSON files rather than a database, because the data is tiny and should
  be easy to inspect and delete.
- No machine learning or LLM. Thresholds and counting rules are
  transparent and testable.
- Not sandboxed. Hardened runtime is on, and the app is ad-hoc signed with
  the camera entitlement.

## 5. What has been verified, and what hasn't

**Verified on this Mac:**

- **72 automated tests** pass (289 checks): `swift build --product
  sway-tests && .build/debug/sway-tests`, with
  `DEVELOPER_DIR=/Library/Developer/CommandLineTools`. They cover:
  - activity and break accounting;
  - sleep, missed sleep notifications and midnight;
  - guided breaks;
  - dedupe, cooldowns, budgets, holds, snoozes and back-off;
  - personalization bounds;
  - persistence;
  - calibration, smoothing and confidence gates;
  - sustained versus brief deviations, the "building" state, hysteresis;
  - tracking loss, camera switch, looking at another monitor;
  - nine regression tests for defects found in an earlier review.

  Posture tests use deterministic synthetic landmark sequences, not real
  camera frames.
- **Performance** (M1 Pro under heavy unrelated load, so upper bounds):
  - Vision takes 7 ms per frame for the face alone and 16 ms with body pose.
  - The posture engine takes about 16 µs per observation.
  - The scheduling and policy tick takes about 2 µs.
  - Idle with the camera off: about 0.16% of one core and 20 MB footprint
    over 5 minutes.
  - Camera-on cost is estimated at about 0.5% of a core. That figure is
    derived, not measured.
- **UI** reviewed as offscreen-rendered PNGs in light and dark.
- **Live use by the owner on 2026-10-26.** Calibration on the FaceTime HD
  camera succeeded. Live readings changed as expected (a lean read +29%).
  The camera ran and stopped as designed.

**Not yet verified:**

- **A full held-lean episode on a real face** through to a delivered
  notification.
- **Notification action clicks** from a real notification.
- **Launch at login** across a logout.
- **Real sleep/wake and lock/unlock.** These are tested only with
  simulated events.
- **Holds during a real call.**
- **The generated `Xcode/Sway.xcodeproj`.** It has never been built,
  because the Xcode license isn't accepted on this Mac.

## 6. Problems found in live use today, and their fixes

| Problem the owner saw | Cause | Fix (commit) |
| --- | --- | --- |
| Leaning forward "does nothing". | By design nothing shows for 5 min, and the UI showed no sign of the countdown. Diagnostics read "+29% (counts at 16%)", and the Movement row read "0.167 (still below 0.060)", which reads backwards. | The engine exposes deviations being timed (`BuildingIssue`). Diagnostics and the menu show "over 16%, counts in 3:20". The Movement row says "moving" or "still". (`dc04fb0`) |
| After a reinstall, "Camera off" and nothing tracked. | The ad-hoc rebuild changed the code signature, macOS dropped the camera permission, and Sway never asked again. | Sway asks once per launch when monitoring is on and permission isn't determined. The UI shows the permission state. The build signs with the bundle id as the designated requirement, and the permission survived the next rebuild. (`8bcf464`, `b26d40d`) |
| The dashboard's posture bars stayed empty while the owner leaned. | Episodes were added to the day only when they ended. | Today's card adds the current episode live and shows a countdown for one being timed. (`bbbcdf8`) |

The pattern behind all three: correct internal behaviour that wasn't visible
to the user. Please look for more of the same.

## 7. Known limitations

- **No Focus or meeting state.** macOS doesn't expose them. Sway treats
  another app using the mic or camera as a likely call. It can't tell
  dictation from a call, or detect screen sharing without the mic.
- **Calibration staleness is caught only when it's large.** A moved
  laptop, monitor or chair is noticed after 10 min only when the face sits
  far to the side or at a very different size. A small move (a few cm up
  or down) still shifts the estimates without warning.
- **Head-down without the reference is ambiguous.** Without the "look at
  the keyboard" step, head-down relies on vertical face position. That
  also changes when the user slouches down in the chair.
- **Shoulders are rarely measurable.** Most laptop cameras don't show both
  shoulders.
- **Ad-hoc signing.** Fine locally. Distribution needs a Developer ID
  signature and notarization.
- **No XCTest.** The test runner is a small custom harness, because the
  Command Line Tools ship no XCTest.

## 8. Where we'd like you to push

1. **Timing defaults.** Are 5 min to count and 8 min to notify too slow
   for a first-time user to trust that it works? A user who leans for
   4 minutes, sits back, and repeats this all day never gets a reminder.
   Is that the right call?
2. **Visibility.** Find other places where Sway is working but looks idle,
   or idle but looks working: holds, budgets, back-off, low confidence,
   the camera off while away.
3. **Short repeated bouts.** The frequent-pattern detector
   (`FrequentPatterns.swift`) is meant to catch "leans for 4 minutes, sits
   back, repeats all day" without flagging ordinary movement. Are its
   limits (4 bouts of 30 s+, 35% of 30+ observed minutes in an hour) too
   strict or too loose? It never sends a notification by itself.
4. **Calibration health.** Can ordinary use (a second monitor, sitting
   far back, a standing desk) look like a moved camera and pause posture
   warnings? Can a real move go unnoticed (see §7)?
5. **False positives.** Watch for:
   - a lean caused by a reading-distance change, such as a larger font or
     a different window;
   - head-down while reading notes on the desk;
   - stillness during focused reading.

   Do the gates (yaw 28°, confidence 0.6, 60% reliability) cover these?
6. **Personalization and back-off.** Silencing now lasts only the rest
   of the day, and long-session reminders ignore budgets and silencing.
   Can the rules still combine so a real, repeated issue goes quiet for
   good?
7. **Sleep, clock and relaunch edges** in `ActivityTracker` and
   `AppModel`, such as state restored after a crash mid-episode or mid
   guided break.
8. **Privacy claims.** Confirm that no pixel buffer is retained or written,
   and that nothing reaches the network.
9. **Wording.** Do any texts imply diagnosis or a medical benefit?

When you report, please give the file and line, a concrete scenario
(inputs, then what the user sees), and whether you reproduced it or
reasoned it from the code.
