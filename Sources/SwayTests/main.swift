import Foundation

let code = runAll([
    ("Activity", activityTests),
    ("Scheduling & notifications", schedulingTests),
    ("Posture", postureTests),
    ("Persistence & content", storeTests),
    ("Review regressions", regressionTests),
    ("Notifications", notificationTests),
    ("Saved-file compatibility", compatibilityTests),
])
exit(code)
