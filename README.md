# Sway

A calm, native macOS menu-bar coach for long days at the computer. It
notices long stretches without movement and, optionally with the camera,
sustained head and shoulder positions. It suggests a concrete adjustment or a
short guided routine at sensible moments, and otherwise stays out of the way.

Sway favours movement and variety over one "correct" posture. It doesn't
diagnose anything, and camera estimates are relative to your own calibration,
not measurements of your spine. For persistent, severe or worsening pain, see
a qualified clinician.

## Install and set up

Sway is built from source on your own Mac. It takes about five minutes.

### 1. What you need

- A Mac on macOS 14 Sonoma or later (Apple Silicon or Intel). It was built and
  tested on macOS 27 on Apple Silicon.
- Apple's Command Line Tools (Swift 5.10 or later). Check with
  `swift --version`; if it isn't found, install them:

  ```bash
  xcode-select --install
  ```

  Full Xcode works too, but isn't needed.

### 2. Build and install

```bash
git clone https://github.com/YassinEldeeb/sway.git
cd sway
scripts/build-app.sh --install
```

This builds `Sway.app`, copies it to `/Applications` and starts it. Running it
again later updates Sway in place: it quits the running copy and starts the
new one, and keeps your data, calibration and permissions.

Sway lives in the **menu bar** (a small figure icon near the clock), not in the
Dock. On first launch a short welcome window opens.

> If the build fails because the Xcode license hasn't been accepted, run
> `sudo xcodebuild -license` once, or ignore it: the script already builds
> with the Command Line Tools.

### 3. Allow notifications (required for reminders)

Without this, reminders only appear inside the menu bar popover.

1. In the welcome window, click **Allow notifications**, then **Allow** in the
   macOS prompt. (Later: menu bar icon → **Allow**, or Sway's Settings →
   Notifications → **Allow…**.)
2. Open **System Settings → Notifications → Sway** and check that:
   - **Allow notifications** is on;
   - the alert style is **Banners** (or **Alerts**), not **None**;
   - **Show in Notification Centre** is on.
3. **Focus / Do Not Disturb** silences banners from every app, Sway included.
   If you work with a Focus on, add Sway under **System Settings → Focus →
   <your Focus> → Allowed Notifications → Apps**.
4. Test it: Sway's **Settings → Notifications → Send a test notification**.
   A banner titled "Sway test notification" should appear within a second.

From Terminal you can also print exactly what macOS allows for Sway and post a
test notification:

```bash
/Applications/Sway.app/Contents/MacOS/Sway --notification-probe
```

It prints the permission, alert style and whether macOS accepted and kept the
test notification. If it says "posted: yes" but you saw no banner, a Focus
mode is on.

### 4. Optional: posture monitoring with the camera

Sway works without a camera: break reminders need no permissions at all.
To add posture hints:

1. Menu bar icon → **Calibrate**, or Settings → Posture → turn on **Posture
   monitoring with the camera**.
2. Click **OK** in the macOS camera prompt.
3. Sit comfortably facing your screen and follow the calibration steps.

Camera frames are analysed in memory and discarded; nothing is recorded or
uploaded. If you denied the prompt, allow Sway in **System Settings →
Privacy & Security → Camera**, or reset the answer and try again:

```bash
tccutil reset Camera dev.sway.coach
```

### 5. Optional: start at login

Sway's **Settings → General → Launch at login**. It needs Sway to be in
`/Applications` (step 2 does that). You'll then see Sway under **System
Settings → General → Login Items**.

### What Sway does not need

No Accessibility, Input Monitoring, Screen Recording, microphone, network or
account access. Activity comes from the system idle timer (seconds since the
last input), never from keystrokes, apps or windows. The "hold during calls"
option only checks whether another app is using the microphone or camera.

### Troubleshooting

| Problem | What to do |
| --- | --- |
| No banners appear | Do step 3 again: permission on, style **Banners**, Focus off or allowing Sway. Run the `--notification-probe` command above. Sway's Settings → Diagnostics lists every decision, including "held" and why. |
| The menu says reminders are held | It says why: paused, quiet hours, a call, a full-screen app, or macOS not showing Sway's notifications. |
| `open` fails with error -600 | The old copy was still quitting. Run `scripts/build-app.sh --install` again: it waits and starts Sway itself. |
| Camera stays off | Allow Sway under Privacy & Security → Camera, then recalibrate from the menu bar. |
| Start again from scratch | Settings → Privacy → **Delete all Sway data…**, then recalibrate. |

### Uninstall

Quit Sway from its menu, then:

```bash
rm -rf /Applications/Sway.app ~/Library/Application\ Support/Sway
tccutil reset All dev.sway.coach
```

If you turned on launch at login, turn it off first in Settings, or remove
Sway from System Settings → General → Login Items.

## Development

Run the tests:

```bash
swift build --product sway-tests && .build/debug/sway-tests
```

To run only some tests, pass part of their name, e.g.
`.build/debug/sway-tests posture`. A name that matches nothing is reported
as an error, not as a passing run.

`scripts/build-app.sh` without `--install` only builds `build/Sway.app`
(release, ad-hoc signed, hardened runtime).

### Xcode

- **`Package.swift`**: open it in Xcode (File → Open) for the `Sway`,
  `sway-tests` and `SwayCore` schemes. This is the simplest way to edit,
  build and debug.
- **`Xcode/Sway.xcodeproj`**: an app target with the real Info.plist,
  entitlements and signing settings, linking `SwayCore` from the local
  package. It's generated by `scripts/generate-xcodeproj.py`; re-run that
  after adding app source files. *It has not been built with Xcode yet, so
  treat it as unverified.* `build-app.sh` is the verified path.

### Developer flags

| Command | What it does |
| --- | --- |
| `Sway --notification-probe` | Prints macOS's notification settings for Sway and posts a test notification. |
| `Sway --benchmark` | Measures Vision, posture-engine and scheduling cost. |
| `SWAY_DATA_DIR=/tmp/demo Sway --seed-demo-data` | Writes two weeks of demo data to that folder. |
| `SWAY_DATA_DIR=/tmp/demo SWAY_NO_CAMERA=1 Sway --snapshots /tmp/shots` | Renders every screen to PNG in light and dark. |

## Features

**Menu bar**: a figure icon that changes when a break or posture hint is
due, a camera mark whenever the camera is on, and an optional work timer.
The popover shows, in order:
- whether coaching is on;
- what needs attention, with one-click actions;
- how long you've been working;
- a countdown to the next break;
- posture status;
- routines, a break, and pause (30 min, 1 h, 2 h, until tomorrow).

**Activity and breaks** (no camera needed):
- Active time comes from the system idle counter. Sway never sees
  keystrokes, apps, windows, the clipboard or browsing.
- Defaults: a movement break every 25 min, a longer break every 55 min, and
  an escalation after 120 min without a real break. Eye rest (20-20-20) is
  opt-in.
- Timers reset only after real time away (2+ min) or a routine or guided
  break you complete. A few seconds of inactivity never count. Sleep, lock
  and wake are handled.

**Smart notifications**, at three levels:
1. Menu bar: every reminder shows here first, with a line saying whether it
   was sent, is waiting (and until when), or is held, and why.
2. Notification: one suggestion with actions (routine, 3-min break, snooze,
   recalibrate, not helpful). Clicking it does its main action.
3. Workstation suggestion: when an issue keeps recurring, once a day, instead
   of repeating the same reminder. It opens the setup assistant at the item
   that fits.

Limits that keep it quiet:
- dedupe, so a reminder is never sent twice;
- a notification is removed as soon as it's no longer true (break taken,
  position changed);
- per-kind cooldowns and 8-minute spacing;
- at most 3 per hour and 14 per day (a 2-hour session reminder is exempt);
- 2 snoozes per reminder;
- backing off to the menu bar after 3 dismissals of the same kind, for the
  rest of that day only.

Reminders are held while another app uses the mic or camera (likely a call),
while a full-screen app is in front, during quiet hours, while paused, and
while macOS doesn't show Sway's notifications (the menu offers "Allow").
When a hold ends, Sway waits 3 minutes and then sends at most the one
reminder that is still current: no burst after a meeting. macOS Focus also
holds them. Settings → Diagnostics keeps a log of every decision.

**Posture monitoring** (optional, experimental):
- Calibration: a guided capture of your comfortable position, an optional
  "look at your keyboard" reference, and a report of what can be measured
  with your camera plus placement warnings.
- What it detects, after several minutes and with hysteresis:
  - head tilted down;
  - leaning toward the screen;
  - head tilted to the side;
  - uneven shoulders (only when they're clearly visible);
  - long stretches with little movement.
- Issues that come back in short bouts (4+ bouts of 30 s or more, over a
  third of an hour with the camera) are noticed too. They lead to one
  workstation suggestion that day, never a notification per bout.
- If the face sits far from where it was calibrated for 10 minutes (the
  screen, camera or chair probably moved), posture warnings stop and the
  menu offers to recalibrate. Ordinary posture changes don't trigger it.
- Low confidence, a missing face, another person in view, or looking at
  another screen never trigger a warning.
- The camera runs only while you're at the computer. It turns off when you
  step away, pause, or lock the Mac, and it is tied to the calibrated camera.

**Guided routines**: 12 routines of 30 s, 1 min, 3 min and 5 min, covering
neck, shoulders, upper back, wrists, eyes, and standing or walking. Each
has animated line drawings, a countdown, repetitions, safety notes, skip
and pause, and "did that help?" feedback.

**Workstation setup assistant**: a checklist covering:
- monitor height, distance, angle and glare;
- external monitors;
- chair, feet and desk;
- keyboard placement and mouse placement;
- forearms, neck and shoulders, and varying position.

Each item has a diagram (a common mistake next to the recommended setup),
an evidence tag and a quick check. Numbers are given as approximate ranges,
not universal requirements. A measurements page turns
the numbers you enter (Sway never estimates them) into suggestions. A
calibration status indicator is included.

**Dashboard**:
- **Today**: active time, longest stretch, breaks, typical stretch, camera
  time, sustained deviations by type, prompts and how you responded, an
  optional comfort check-in (neck, upper back, lower back, eyes; 0–10), and
  a timeline.
- **Trends**: 7, 14 or 30 days, with comfort shown next to days of
  workstation changes. It never claims cause and effect.
- **Insights**: what Sway adapted and why, recurring patterns, and comfort
  over time.

Every metric has a plain definition. There is no posture score.

**Personalization**: transparent, bounded rules from your responses. It can
space out reminders you keep dismissing, desensitize posture issues you mark
not helpful, and note when you usually break on your own. It never makes
Sway more insistent, and it can be reset.

**Privacy**:
- Everything stays local: no network, account or analytics.
- Camera frames are analysed in memory and discarded, never recorded or
  stored.
- Daily files hold only times and counts.
- Retention is 90 days by default, and one button deletes all data.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how it fits together and why.
- [docs/EVIDENCE.md](docs/EVIDENCE.md): what each recommendation rests on.
- [docs/VALIDATION.md](docs/VALIDATION.md): the manual test procedure for hardware and permissions.
- [PROGRESS.md](PROGRESS.md): status, test results, measured performance, known issues and next steps.
