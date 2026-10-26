import Foundation

let code = runAll([
    ("Activity", activityTests),
    ("Scheduling & notifications", schedulingTests),
    ("Posture", postureTests),
    ("Persistence & content", storeTests),
])
exit(code)
