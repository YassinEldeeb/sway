# What Sway's recommendations rest on

Sway labels every recommendation with where it comes from. This page explains
the labels and the main sources. Sway is not a medical device and makes no
claim to prevent injury or correct posture.

## Evidence-informed

Workstation guidance from occupational-health bodies:

- **OSHA, Computer Workstations eTool**: monitor top at or slightly below
  eye level; viewing distance about 20–40 in (50–100 cm); screen
  perpendicular to windows to avoid glare; keyboard and mouse close and at
  elbow height; feet supported; forearm support with relaxed shoulders.
- **CCOHS, Office Ergonomics**: monitor placement with the centre about
  15–20° below horizontal eye level; bifocal users lower; avoid prolonged
  static postures and change position often.
- **ANSI/HFES 100-2007** and **ISO 9241-5**: ranges for viewing distance,
  screen height and angle, seat and work-surface heights.

Sway applies these in its setup assistant, which the user fills in by hand.
It never infers physical measurements from the camera. The diagrams and
texts give these numbers as approximate ranges ("about", "roughly", "for
most people"), not universal requirements; elbow angle follows OSHA's
neutral range (roughly 90–120°).

## Practical heuristics (configurable)

- **Break timing**: a short movement break about every 20–30 minutes and a
  longer break about every 50–60 minutes. Guidance consistently recommends
  breaking up prolonged sitting and screen work with frequent short breaks
  and changes of position. There is no single validated interval, so these
  are defaults the user can change.
- **20-20-20 eye rest**: a widely used convention, recommended by the
  American Academy of Ophthalmology and the American Optometric Association
  for digital eye strain. It is off by default and opt-in.
- **"Movement over the perfect posture"**: the current consensus is that no
  single sitting posture is protective and that variation matters. Sway
  therefore flags *sustained* deviations and *stillness*, never brief ones,
  and never scores posture.
- **Routines**: gentle, within comfortable range, no bouncing or forced neck
  movements, each step skippable, with a stop rule for pain, numbness,
  tingling or dizziness.

## Experimental camera estimates

- Head position, face size, head roll and shoulder line are measured
  relative to a calibration taken with one camera in one setup. They
  approximate *changes* in how you sit, not spinal angles.
- Thresholds are conservative by default: a deviation must last 5 minutes
  (10 for shoulders) before it counts, and a notification needs 3 more
  minutes. Personalization can only make them less sensitive.
- When confidence is low, Sway says so instead of warning.
- **Repeated short deviations** are a heuristic of Sway's own, set to be
  conservative: in a rolling hour with at least 30 minutes of reliable
  camera time, 4+ separate bouts of 30 s or more covering over a third of
  it (little movement: 70% of the time, in 2+ stretches). Shorter glances
  and shifts are treated as the ordinary movement the guidance encourages.
  The result is one suggestion to look at the workstation, never a
  notification per bout, and the limits are configurable.
- **Calibration health** is a heuristic too: only a large, lasting change
  (the face far to the side, or at under 0.6× or over 1.8× its calibrated
  size, for most of 10 minutes) is treated as a moved setup. Leaning in
  (+16% counts) and sitting back stay inside it. When it trips, posture
  warnings stop rather than guess.

## Outcomes

Comfort is something to watch over time, not something the camera can see.
The optional daily check-in records neck, upper back, lower back and eye
discomfort on a 0–10 scale; any area can be left out, and scores of 7 or
more suggest seeing a clinician. Trends show it next to work, breaks and the
days the workstation changed, without implying cause and effect. Sway
doesn't tune reminder frequency from discomfort scores.
