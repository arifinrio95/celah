import SwiftUI
import CoreImage.CIFilterBuiltins

/// Phone Remote, inside the board: one switch, one QR, the paired phones.
struct RemotePanel: View {
    @ObservedObject var ctl: NotchController
    @EnvironmentObject var remote: RemoteService
    @EnvironmentObject var clock: Clock

    var body: some View {
        let p = D.p
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Phone Remote").font(D.serif(20).italic()).foregroundStyle(p.ink)
                Text("your Mac, from anywhere").font(D.rounded(11.5, .semibold)).foregroundStyle(p.ink3)
                Spacer()
                Toggle("", isOn: $remote.enabled).toggleStyle(.switch).labelsHidden().tint(p.ok).controlSize(.small)
                Orb(symbol: "xmark", size: 24) { remote.panelOpen = false }
            }
            HStack(alignment: .top, spacing: 14) {
                qrCard
                VStack(alignment: .leading, spacing: 10) {
                    status
                    if !remote.canSee || !remote.canControl { permissions }
                    if remote.devices.isEmpty {
                        guide
                    } else {
                        devices
                    }
                    Spacer(minLength: 0)
                    Text("Each phone gets its own key. Keep the Mac awake so the phone can reach it.")
                        .font(D.rounded(10.5)).foregroundStyle(p.ink4).lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(p.card)
                .shadow(color: p.cardShadow, radius: 18, y: 10)
        }
        .onAppear { ctl.cheer(.happy, for: 1.2); remote.freshenPairing() }
    }

    // MARK: - QR

    @ViewBuilder private var qrCard: some View {
        let p = D.p
        let online: Bool = { if case .online = remote.tunnel { return true }; return false }()
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
                if online, let link = remote.pairLink, let img = QR.image(link) {
                    Image(nsImage: img).interpolation(.none).resizable().frame(width: 176, height: 176)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: remote.enabled ? "antenna.radiowaves.left.and.right" : "iphone.slash")
                            .font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.black.opacity(0.35))
                            .symbolEffect(.pulse, isActive: remote.enabled)
                        Text(remote.enabled ? "Opening the tunnel…" : "Switch on to pair")
                            .font(D.rounded(11.5, .semibold)).foregroundStyle(Color.black.opacity(0.45))
                    }
                }
            }
            .frame(width: 196, height: 196)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(p.cardStroke))
            .animation(.easeInOut(duration: 0.25), value: remote.pairLink)
            if online, let exp = remote.pairExpires {
                let left = max(0, Int(exp.timeIntervalSince(clock.now)))
                HStack(spacing: 6) {
                    Text(left > 0 ? "works once · \(left / 60):\(String(format: "%02d", left % 60))" : "expired")
                        .font(D.mono(10.5)).foregroundStyle(left > 0 ? p.ink3 : p.danger)
                    Orb(symbol: "arrow.clockwise", size: 20) { remote.newPairing() }.help("New code")
                    if let link = remote.pairLink {
                        Orb(symbol: "doc.on.doc", size: 20) {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string)
                            ctl.cheer(.happy, for: 0.8)
                        }.help("Copy the pairing link")
                    }
                }
            }
        }
    }

    // MARK: - right column

    @ViewBuilder private var status: some View {
        let p = D.p
        HStack(spacing: 8) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
                .shadow(color: dotColor.opacity(0.8), radius: remote.connected.isEmpty ? 0 : 5)
            Text(statusText).font(D.rounded(12.5, .semibold)).foregroundStyle(p.ink2).lineLimit(2)
            Spacer(minLength: 0)
            if !remote.connected.isEmpty {
                Text("LIVE").font(D.label(9.5)).tracking(1).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(p.ok))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.track.opacity(0.6)))
        if let w = remote.warning {
            Text(w).font(D.rounded(11)).foregroundStyle(p.danger).lineLimit(2)
        }
    }

    /// Shown until both are granted to *this* copy of Celah.
    @ViewBuilder private var permissions: some View {
        let p = D.p
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                permChip("Screen Recording", ok: remote.canSee, why: "so the phone can see") { remote.openSettings(.screen) }
                permChip("Accessibility", ok: remote.canControl, why: "so the phone can click and type") { remote.openSettings(.accessibility) }
            }
            Text("Already on in Settings? An older Celah may be listed there. Select Celah, remove it with −, then allow again. Screen Recording takes effect after Celah restarts.")
                .font(D.rounded(10.5)).foregroundStyle(p.ink3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permChip(_ name: String, ok: Bool, why: String, open: @escaping () -> Void) -> some View {
        let p = D.p
        return Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? p.ok : D.amber)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(D.rounded(11.5, .semibold)).foregroundStyle(p.ink)
                    Text(ok ? "allowed" : "allow \(why)").font(D.rounded(10)).foregroundStyle(p.ink3)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.track.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ok ? Color.clear : D.amber.opacity(0.6)))
        }
        .buttonStyle(PressScale())
        .disabled(ok)
    }

    private var guide: some View {
        let p = D.p
        return VStack(alignment: .leading, spacing: 7) {
            step(1, "Scan the code with your phone's camera.")
            step(2, "Add the page to the Home Screen.")
            step(3, "Open it anywhere: 4G, café Wi-Fi, another city.")
            HStack(spacing: 6) {
                ForEach(["Touch", "Trackpad", "Keyboard", "Zoom"], id: \.self) { t in
                    Text(t).font(D.rounded(10.5, .semibold)).foregroundStyle(p.ink3)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().stroke(p.cardStroke))
                }
            }
            .padding(.top, 4)
        }
        .font(D.rounded(12)).foregroundStyle(p.ink2)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(D.rounded(10.5, .heavy)).foregroundStyle(Color.black.opacity(0.78))
                .frame(width: 18, height: 18).background(Circle().fill(D.p.accent))
            Text(text)
        }
    }

    @ViewBuilder private var devices: some View {
        let p = D.p
        VStack(alignment: .leading, spacing: 6) {
            Text("PAIRED PHONES").font(D.label()).tracking(1.2).foregroundStyle(p.ink4)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(remote.devices) { d in
                        let live = remote.connected.contains(d.name)
                        HStack(spacing: 10) {
                            Image(systemName: "iphone").font(.system(size: 13, weight: .semibold)).foregroundStyle(live ? p.ok : p.ink3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.name).font(D.rounded(12.5, .semibold)).foregroundStyle(p.ink)
                                Text(live ? "Watching now" : d.lastSeen.map { "Last seen " + $0.formatted(.relative(presentation: .named)) } ?? "Never connected")
                                    .font(D.rounded(10.5)).foregroundStyle(live ? p.ok : p.ink4)
                            }
                            Spacer()
                            RemoveButton { remote.revoke(d) }
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.track.opacity(0.6)))
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var statusText: String {
        switch remote.tunnel {
        case .off: return "Off. Nobody can reach this Mac."
        case .preparing(let m): return m
        case .connecting: return "Opening the tunnel…"
        case .online: return remote.connected.isEmpty ? "Ready for your phone" : "Live on \(remote.connected.joined(separator: ", "))"
        case .failed(let m): return m
        }
    }
    private var dotColor: Color {
        switch remote.tunnel {
        case .online: return D.p.ok
        case .failed: return D.p.danger
        case .off: return D.p.ink4
        default: return D.amber
        }
    }
}

/// "Remove", then "Remove?" for three seconds, like Force Quit.
private struct RemoveButton: View {
    let action: () -> Void
    @State private var asking = false
    var body: some View {
        Button(asking ? "Remove?" : "Remove") {
            if asking { action() } else {
                asking = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { asking = false }
            }
        }
        .buttonStyle(.plain)
        .font(D.rounded(11, .semibold)).foregroundStyle(D.p.danger)
    }
}

enum QR {
    static func image(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: out.extent.width / 2, height: out.extent.height / 2))
    }
}
