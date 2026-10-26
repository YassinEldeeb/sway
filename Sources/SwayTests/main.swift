import Foundation

// Fixtures are written in UTC, and "today" depends on the time zone: pin it
// so results don't depend on the machine. Tests that are about local days
// set their own zone and restore this one.
NSTimeZone.default = TimeZone(identifier: "UTC")!

let code = runAll([
    ("Activity", activityTests),
    ("Scheduling & notifications", schedulingTests),
    ("Posture", postureTests),
    ("Persistence & content", storeTests),
    ("Review regressions", regressionTests),
    ("Notifications", notificationTests),
    ("Saved-file compatibility", compatibilityTests),
    ("Patterns & calibration health", patternTests),
])
exit(code)
