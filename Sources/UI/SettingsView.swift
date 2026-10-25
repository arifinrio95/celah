import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var prayer: PrayerService
    @AppStorage("awake.batteryMin") private var batteryMin = 15
    @AppStorage("awake.thermalGuard") private var thermalGuard = true
    @AppStorage("meeting.prompt") private var meetingPrompt = ""
    @AppStorage("notch.openDelay") private var openDelay = 0.0

    var body: some View {
        Form {
            Section("Look") {
                Picker("Board", selection: $settings.look) {
                    Text("Porcelain — paper under the notch").tag("porcelain")
                    Text("Ink — smoked glass").tag("ink")
                }
                .pickerStyle(.radioGroup)
            }
            Section("Board modules") {
                let order = settings.modules + BoardModule.allCases.filter { !settings.modules.contains($0) }
                ForEach(order) { m in moduleRow(m) }
                HStack {
                    Text("Up to \(BoardLayout.maxModules). The grid adjusts automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { settings.resetModules() }
                }
            }
            Section("Prayer times") {
                Toggle("Use device location (GPS)", isOn: $settings.useGPS)
                Picker("City", selection: $settings.cityID) {
                    ForEach(Cities.all) { Text($0.name).tag($0.id) }
                }
                .disabled(settings.useGPS)
                Stepper("Buffer: \(settings.ihtiyat) min", value: $settings.ihtiyat, in: 0...5)
                Text("Method: Kemenag RI (Fajr 20°, Isha 18°).").font(.caption).foregroundStyle(.secondary)
            }
            Section("Meeting prompt") {
                TextEditor(text: $meetingPrompt)
                    .font(.system(size: 11))
                    .frame(height: 130)
                HStack {
                    Text("Sent to Claude or Codex with each recording. Empty uses the default.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { meetingPrompt = "" }
                }
            }
            Section("Keep Awake") {
                Stepper("Turn off below \(batteryMin)% battery", value: $batteryMin, in: 5...50, step: 5)
                Toggle("Turn off when the Mac runs hot", isOn: $thermalGuard)
            }
            Section("Reminders") {
                Toggle("Prayer notifications", isOn: $settings.prayerNotify)
                Stepper("Remind \(settings.preMinutes) min before", value: $settings.preMinutes, in: 0...30, step: 5)
                    .disabled(!settings.prayerNotify)
            }
            Section("Notch") {
                Picker("Open the board", selection: $openDelay) {
                    Text("Instantly on hover").tag(0.0)
                    Text("After 0.3 s of hover").tag(0.3)
                    Text("After 0.6 s of hover").tag(0.6)
                    Text("After 1 s of hover").tag(1.0)
                    Text("Only when I click the notch").tag(-1.0)
                }
                Text("A short delay stops the board from opening when you only pass the notch on the way to the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show wings for music and prayer", isOn: $settings.wings)
                Toggle("Open Celah at login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { _ in (NSApp.delegate as? AppDelegate)?.toggleLaunchAtLogin() }))
            }
            Section {
                HStack {
                    Button("Reload data") { (NSApp.delegate as? AppDelegate)?.reloadAll() }
                    Spacer()
                    Button("Quit Celah") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 620)
        .onChange(of: settings.cityID) { _, _ in prayer.recompute() }
        .onChange(of: settings.useGPS) { _, _ in prayer.locationModeChanged() }
        .onChange(of: settings.ihtiyat) { _, _ in prayer.recompute() }
        .onChange(of: settings.prayerNotify) { _, _ in prayer.recompute() }
        .onChange(of: settings.preMinutes) { _, _ in prayer.recompute() }
    }

    private func moduleRow(_ m: BoardModule) -> some View {
        let on = settings.isOn(m)
        let full = !on && settings.modules.count >= BoardLayout.maxModules
        let index = settings.modules.firstIndex(of: m)
        return HStack(spacing: 8) {
            Toggle(m.title, isOn: Binding(get: { on }, set: { settings.setOn(m, $0) }))
                .disabled(full)
            Spacer()
            if let index {
                Button { settings.move(m, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                Button { settings.move(m, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(index == settings.modules.count - 1)
            }
        }
    }
}
