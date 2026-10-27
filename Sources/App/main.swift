import AppKit

let cliArgs = CommandLine.arguments

// `Celah --pin` toggles a pinned (always open) board on the running instance; handy for screenshots.
if cliArgs.contains("--pin") || cliArgs.contains("--toggle") {
    DistributedNotificationCenter.default().postNotificationName(AppDelegate.pinNotification, object: nil,
                                                                 userInfo: nil, deliverImmediately: true)
    exit(0)
}
// `Celah --settings` opens the settings window of the running instance.
if cliArgs.contains("--settings") {
    DistributedNotificationCenter.default().postNotificationName(AppDelegate.settingsNotification, object: nil,
                                                                 userInfo: nil, deliverImmediately: true)
    exit(0)
}
if cliArgs.contains("--meetings") {
    DistributedNotificationCenter.default().postNotificationName(AppDelegate.meetingsNotification, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
if cliArgs.contains("--quran") {
    DistributedNotificationCenter.default().postNotificationName(AppDelegate.quranNotification, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
// `Celah --remote [--shot file.png]` opens Phone Remote; --shot saves a picture of the window (debug aid).
if cliArgs.contains("--remote") {
    let shot = cliArgs.firstIndex(of: "--shot").flatMap { cliArgs.indices.contains($0 + 1) ? cliArgs[$0 + 1] : nil }
    DistributedNotificationCenter.default().postNotificationName(AppDelegate.remoteNotification, object: nil,
                                                                 userInfo: shot.map { ["shot": $0] }, deliverImmediately: true)
    exit(0)
}
if cliArgs.contains("--tasks") {
    DistributedNotificationCenter.default().postNotificationName(AppDelegate.tasksNotification, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
// `Celah --diag` prints what every service sees (no UI) and exits.
if cliArgs.contains("--diag") {
    Diagnostics.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
