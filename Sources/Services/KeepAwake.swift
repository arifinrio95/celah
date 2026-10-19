import AppKit
import IOKit
import IOKit.pwr_mgt
import IOKit.ps
import UserNotifications

/// Keeps the Mac awake, like Amphetamine.
/// "Awake" holds a power assertion, so idle sleep stops while the display may still sleep.
/// "Lid closed" also turns sleep off system-wide with `pmset`, which needs an administrator password.
/// Guards turn everything off when the battery is low, the Mac runs hot, or the timer ends.
final class KeepAwake: ObservableObject {
    enum Mode: String, Equatable { case off, awake, lidClosed }

    static let durations: [(label: String, minutes: Int?)] = [
        ("Until off", nil), ("1 hr", 60), ("2 hr", 120), ("4 hr", 240),
    ]

    @Published private(set) var mode: Mode = .off
    @Published private(set) var endsAt: Date?
    @Published private(set) var message: String?
    @Published var panelOpen = false
    @Published private(set) var minutes: Int?

    private var assertion: IOPMAssertionID = 0
    private var hasAssertion = false
    private var timer: Timer?
    private let lidKey = "awake.lidActive"

    var isActive: Bool { mode != .off }
    /// True when this app has turned system sleep off with pmset and not yet turned it back on.
    var sleepDisabled: Bool { UserDefaults.standard.bool(forKey: lidKey) }
    var batteryThreshold: Int {
        let v = UserDefaults.standard.object(forKey: "awake.batteryMin") == nil ? 15 : UserDefaults.standard.integer(forKey: "awake.batteryMin")
        return min(50, max(5, v))
    }
    var thermalGuard: Bool {
        UserDefaults.standard.object(forKey: "awake.thermalGuard") == nil ? true : UserDefaults.standard.bool(forKey: "awake.thermalGuard")
    }

    /// Runs at launch: if a previous run left sleep disabled, say so so the user can restore it.
    func recoverIfNeeded() {
        guard sleepDisabled, mode == .off else { return }
        message = "Sleep is still disabled from last time."
    }

    /// Chooses a mode with the selected duration.
    func choose(_ target: Mode) {
        message = nil
        if target == .off { turnOff(); return }
        acquireAssertion()
        if target == .lidClosed {
            if setLidClosed(true) {
                UserDefaults.standard.set(true, forKey: lidKey)
                mode = .lidClosed
            } else {
                mode = .awake
                message = "Lid-closed mode needs your administrator password."
            }
        } else {
            if !disableLidMode() { message = "Sleep is still disabled. Tap Restore sleep." }
            mode = .awake
        }
        startTimer()
        endsAt = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
    }

    /// Changes the duration. If a mode is active, the countdown restarts from now.
    func setDuration(_ m: Int?) {
        minutes = m
        if isActive { endsAt = m.map { Date().addingTimeInterval(Double($0) * 60) } }
    }

    func turnOff() {
        releaseAssertion()
        if !disableLidMode() { message = "Sleep is still disabled. Tap Restore sleep." }
        timer?.invalidate()
        timer = nil
        mode = .off
        endsAt = nil
    }

    func restoreSleep() {
        message = disableLidMode() ? nil : "Administrator password was not given. Sleep is still disabled."
    }

    /// Called on quit so that the app never leaves the Mac unable to sleep.
    func shutdown() {
        releaseAssertion()
        _ = disableLidMode()
    }

    // MARK: - Assertions and pmset

    private func acquireAssertion() {
        guard !hasAssertion else { return }
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "Celah keep awake" as CFString, &assertion)
        hasAssertion = r == kIOReturnSuccess
    }

    private func releaseAssertion() {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertion)
        hasAssertion = false
    }

    @discardableResult
    private func disableLidMode() -> Bool {
        guard sleepDisabled else { return true }
        guard setLidClosed(false) else { return false }
        UserDefaults.standard.set(false, forKey: lidKey)
        return true
    }

    static let sudoersPath = "/etc/sudoers.d/celah-pmset"
    var helperInstalled: Bool { FileManager.default.fileExists(atPath: Self.sudoersPath) }

    /// One-time setup. Installs a sudoers rule that lets this user run exactly the two pmset commands
    /// below without a password. Asks for the administrator password once, then never again.
    @discardableResult
    func installHelper() -> Bool {
        let rule = "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let tmp = "/tmp/celah-sudoers.$$"
        let script = "printf '%s\\n' '\(rule)' > \(tmp) && /usr/sbin/visudo -cf \(tmp) && /usr/bin/install -m 440 -o root -g wheel \(tmp) \(Self.sudoersPath); rm -f \(tmp)"
        guard runAsAdmin(script), helperInstalled else {
            message = "Setup was cancelled. Lid-closed mode will ask for your password."
            return false
        }
        message = "Lid-closed mode is set up. No more password prompts."
        return true
    }

    private func runAsAdmin(_ shell: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        _ = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&err)
        if let err {
            Log.write("admin command failed: \(err[NSAppleScript.errorNumber] ?? "?")")
            return false
        }
        return true
    }

    /// Uses the sudoers rule when installed, so there is no prompt. Otherwise falls back to the password dialog.
    private func setLidClosed(_ on: Bool) -> Bool {
        let v = on ? "1" : "0"
        if helperInstalled {
            let r = Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", v], timeout: 10)
            if r.status == 0 { return true }
            Log.write("sudo pmset disablesleep=\(v) failed status=\(r.status) err=\(r.err)")
            return false
        }
        return runAsAdmin("/usr/bin/pmset -a disablesleep \(v)")
    }

    // MARK: - Guards

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.checkGuards() }
        timer?.tolerance = 5
    }

    private func checkGuards() {
        guard isActive else { return }
        if let endsAt, Date() >= endsAt {
            turnOff()
            notify("Keep Awake ended. Your Mac can sleep again.")
            return
        }
        if let battery = Self.battery(), !battery.onAC, battery.percent <= batteryThreshold {
            turnOff()
            message = "Battery at \(battery.percent)%. Keep Awake turned off."
            notify(message ?? "")
            return
        }
        let heat = ProcessInfo.processInfo.thermalState
        if thermalGuard, heat == .serious || heat == .critical {
            turnOff()
            message = "Mac is running hot. Keep Awake turned off."
            notify(message ?? "")
        }
    }

    static func battery() -> (percent: Int, onAC: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (cap * 100 / max, onAC)
        }
        return nil
    }

    private func notify(_ text: String) {
        let c = UNMutableNotificationContent()
        c.title = "Celah"
        c.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
