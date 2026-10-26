# Manual validation

Automated tests cover the logic (`swift run sway-tests`). These steps cover
what needs your hardware, your permissions or your eyes. Each step says
what to expect. Copy the checklist into an issue or note and tick it off.

Build and launch first:

```bash
scripts/build-app.sh --install   # builds and copies to /Applications
open /Applications/Sway.app
```

## 1. First launch and menu bar
- [ ] A figure icon appears in the menu bar. There is no Dock icon.
- [ ] The welcome window opens. "Allow notifications" shows the macOS prompt.
- [ ] Clicking the icon opens the popover instantly. "Working for" counts up.

## 2. Activity and breaks
- [ ] Work for 2–3 minutes: "Today" active time increases.
- [ ] Stop touching the keyboard and mouse for 3 minutes, then come back. The
      dashboard shows one more break, and "Working for" restarts from ~0.
- [ ] Idle for 30–60 seconds and return: no break is counted.
- [ ] Settings → Breaks: set "Movement break every" to 10 min. After 10 min
      of work, a notification arrives with "Start 1-min routine / Take a
      3-min break / Snooze / Not helpful".
- [ ] Snooze it: it returns after 10 minutes. On the second return, Snooze
      is no longer offered (the default limit is 2 snoozes).
- [ ] Dismiss three movement reminders in a row (close the notification
      banner). Further movement reminders that day appear only in the popover.

## 3. Sleep and wake
- [ ] Note "Working for", close the lid (or Apple menu → Sleep) for ≥ 5
      minutes, and wake. The popover shows a fresh stretch, and the
      dashboard counts a break with source "sleep".
- [ ] Lock the screen (⌃⌘Q) for ≥ 2 minutes and unlock: same behaviour.

## 4. Interruption handling
- [ ] Join a video call (or open Voice Memos and record). The popover shows
      "Microphone or camera in use by another app", and no notifications
      arrive while it lasts.
- [ ] Make an app full screen (e.g. Keynote play, or a full-screen video).
      The popover shows "A full-screen app is in front".
- [ ] Turn on a Focus mode: macOS holds Sway's notifications in Notification
      Center.
- [ ] Pause for 30 minutes from the popover: the icon changes to a pause
      symbol, and the camera turns off.

## 5. Posture monitoring (camera)
- [ ] Popover → Calibrate. The welcome text explains what is and isn't
      measured. Start: macOS asks for camera access, citing the usage text.
- [ ] The live preview shows you, and the "Face found" chip turns green.
      Capture → hold still 8 s → optional "look at your keyboard" 4 s → the
      review lists what's measurable and any placement warnings.
- [ ] With only your head in frame, "Uneven shoulders" shows as not
      measurable.
- [ ] Save: the menu-bar icon shows a small camera mark, and the macOS green
      camera light is on.
- [ ] Settings → Diagnostics shows "Frames analysed" increasing about every
      2 s, plus Vision time per frame.
- [ ] Lean toward the screen for 10 s: nothing happens.
- [ ] Lean in clearly (face noticeably bigger) for ~6 minutes. Diagnostics
      "Lean toward screen" stays above its threshold, the popover shows the
      issue, and after ~3 more minutes a gentle notification arrives.
- [ ] Sit back: the issue clears within ~30 s.
- [ ] Walk away for 3 minutes: the camera light turns off (you're away), then
      turns back on when you return and type.
- [ ] Cover the camera or turn off the lights: the status reads "Looking for
      you" or "Low confidence", and no posture prompt appears.
- [ ] Unplug an external calibrated camera: the status reads "Calibrated
      camera not connected". Plug it back in: monitoring resumes within ~30 s.
- [ ] Choose a different camera in Settings → Posture without
      recalibrating: the status reads "Recalibrate for this camera", and the
      camera stays off.
- [ ] System Settings → Privacy → Camera: turn Sway off. The popover reports
      access denied, and the camera stays off.

## 6. Routines and setup
- [ ] Popover → Routines → "Desk mobility minute": the figure animates, the
      ring counts down, and Space pauses. After it ends, "Did that help?"
      appears, and the dashboard's Routines count increases.
- [ ] Setup assistant: mark items, and enter a viewing distance of 35 cm.
      The suggestions mention it's closer than the usual 50–100 cm.

## 7. Data and privacy
- [ ] `ls ~/Library/Application\ Support/Sway/days` shows small JSON files.
      Open one: it holds only times and counts.
- [ ] Settings → Privacy → Delete all Sway data → confirm. The folder is
      removed (and recreated with defaults), calibration is gone, and the
      dashboard is empty.

## 8. A working day
- [ ] Leave Sway running for a full day. Settings → Diagnostics should show
      CPU well under 1% of one core when the camera is off, and memory
      stable (no steady growth). Activity Monitor's "Energy Impact" for Sway
      should stay low.
- [ ] Launch at login: enable it in Settings → General, log out and in, and
      check that Sway starts. If macOS asks, approve it in System Settings →
      General → Login Items.
