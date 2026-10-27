import SwiftUI
import CoreImage.CIFilterBuiltins

/// Phone Remote: one switch, one QR, a list of phones.
struct RemoteWindow: View {
    @EnvironmentObject var remote: RemoteService
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let p = D.p
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone Remote").font(D.serif(26, .semibold)).foregroundStyle(p.ink)
                    Text("See and control this Mac from your phone, from anywhere.")
                        .font(D.rounded(12)).foregroundStyle(p.ink3)
                }
                Spacer()
                Toggle("", isOn: $remote.enabled).toggleStyle(.switch).labelsHidden().tint(p.ok)
            }

            status

            if remote.enabled, case .online = remote.tunnel { pairing }

            if !remote.devices.isEmpty { devices }

            Spacer(minLength: 0)
            Text("Only phones you pair can connect, each with its own key. The link travels through a Cloudflare tunnel, and the Mac must stay awake for it to work.")
                .font(D.rounded(10.5)).foregroundStyle(p.ink4).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 440, height: 580, alignment: .top)
        .background(LinearGradient(colors: [p.trayTop, p.trayBottom], startPoint: .top, endPoint: .bottom))
        .onReceive(tick) { now = $0 }
    }

    @ViewBuilder private var status: some View {
        let p = D.p
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 9, height: 9)
            Text(statusText).font(D.rounded(12.5, .semibold)).foregroundStyle(p.ink2).lineLimit(2)
            Spacer()
            if !remote.connected.isEmpty {
                Text("\(remote.connected.count) watching").font(D.label(10)).foregroundStyle(p.accentInk)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(p.accent))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.cardStroke))
        if let w = remote.warning {
            Text(w).font(D.rounded(11)).foregroundStyle(p.danger)
        }
    }

    private var statusText: String {
        switch remote.tunnel {
        case .off: return "Off"
        case .preparing(let m): return m
        case .connecting: return "Opening the tunnel…"
        case .online: return remote.connected.isEmpty ? "Ready. Pair a phone below." : "Live on \(remote.connected.joined(separator: ", "))"
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

    @ViewBuilder private var pairing: some View {
        let p = D.p
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
                if let link = remote.pairLink, let img = QR.image(link) {
                    Image(nsImage: img).interpolation(.none).resizable().frame(width: 150, height: 150)
                }
            }
            .frame(width: 172, height: 172)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(p.cardStroke))
            VStack(alignment: .leading, spacing: 8) {
                Text("Pair a phone").font(D.rounded(15, .bold)).foregroundStyle(p.ink)
                Text("Scan with the phone's camera, then add the page to the Home Screen.")
                    .font(D.rounded(11.5)).foregroundStyle(p.ink3).fixedSize(horizontal: false, vertical: true)
                if let exp = remote.pairExpires {
                    let left = max(0, Int(exp.timeIntervalSince(now)))
                    Text(left > 0 ? "Works once · \(left / 60):\(String(format: "%02d", left % 60)) left" : "Expired")
                        .font(D.mono(10.5)).foregroundStyle(left > 0 ? p.ink3 : p.danger)
                }
                HStack(spacing: 8) {
                    Pill(symbol: "arrow.clockwise", text: "New code") { remote.newPairing() }
                    if let link = remote.pairLink {
                        Pill(symbol: "doc.on.doc", text: "Copy link") {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var devices: some View {
        let p = D.p
        VStack(alignment: .leading, spacing: 8) {
            Text("PAIRED PHONES").font(D.label()).tracking(1.2).foregroundStyle(p.ink4)
            ForEach(remote.devices) { d in
                HStack(spacing: 10) {
                    Image(systemName: "iphone").foregroundStyle(remote.connected.contains(d.name) ? p.ok : p.ink3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.name).font(D.rounded(12.5, .semibold)).foregroundStyle(p.ink)
                        Text(d.lastSeen.map { "Last seen " + $0.formatted(.relative(presentation: .named)) } ?? "Never connected")
                            .font(D.rounded(10.5)).foregroundStyle(p.ink4)
                    }
                    Spacer()
                    Button("Remove") { remote.revoke(d) }.buttonStyle(.plain)
                        .font(D.rounded(11, .semibold)).foregroundStyle(p.danger)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.card))
            }
        }
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
