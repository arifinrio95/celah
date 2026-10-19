import SwiftUI
import AppKit

/// Clipboard history as a stack of paper slips. Click a slip to copy it back.
struct ClipboardPanel: View {
    @EnvironmentObject var clip: ClipboardStore

    var body: some View {
        let p = D.p
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Clipboard").font(D.serif(20).italic()).foregroundStyle(p.ink)
                Text(clip.flash ?? "\(clip.items.count) slips").font(D.rounded(11.5, .semibold)).foregroundStyle(clip.flash != nil ? p.ok : p.ink3)
                    .contentTransition(.opacity)
                Spacer()
                Pill(symbol: clip.paused ? "play.fill" : "pause.fill", text: clip.paused ? "Paused" : "Listening",
                     on: !clip.paused, tint: clip.paused ? p.danger : p.ok) { clip.paused.toggle() }
                Orb(symbol: "trash", size: 24) { withAnimation(D.snappy) { clip.clearUnpinned() } }.help("Clear unpinned")
                Orb(symbol: "xmark", size: 24) { clip.panelOpen = false }
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 10.5, weight: .bold)).foregroundStyle(p.ink3)
                TextField("", text: $clip.query)
                    .textFieldStyle(.plain).font(D.rounded(12.5, .medium)).foregroundStyle(p.ink)
                    .overlay(alignment: .leading) {
                        if clip.query.isEmpty { Text("Search text or app… click a slip to copy, pin to keep").font(D.rounded(12.5, .medium)).foregroundStyle(p.ink3).allowsHitTesting(false) }
                    }
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(Capsule().fill(p.track))
            if clip.visible.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text(clip.paused ? "Not listening right now." : (clip.query.isEmpty ? "Copy something. I'll keep it." : "No slip matches."))
                        .font(D.serif(15).italic()).foregroundStyle(p.ink3)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(clip.visible) { item in ClipSlip(item: item) }
                    }
                    .padding(.bottom, 4)
                }
            }
            if !clip.canAutoPaste {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                } label: {
                    Label("Turn on auto-paste in Accessibility", systemImage: "hand.point.up.left.fill")
                        .font(D.rounded(10.5, .semibold)).foregroundStyle(p.accentInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(p.card)
                .shadow(color: p.cardShadow, radius: 18, y: 10)
        }
    }
}

private struct ClipSlip: View {
    let item: ClipItem
    @EnvironmentObject var clip: ClipboardStore
    @State private var hover = false
    @State private var copied = false

    var body: some View {
        let p = D.p
        HStack(spacing: 10) {
            if item.kind == .image {
                ClipThumb(file: item.imageFile).frame(width: 44, height: 30)
            } else {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(p.ink3)
                    .frame(width: 26, height: 26).background(Circle().fill(p.track))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(D.rounded(12, .semibold)).foregroundStyle(p.ink).lineLimit(1)
                Text(meta).font(D.rounded(9.5, .medium)).foregroundStyle(p.ink3).lineLimit(1)
            }
            Spacer(minLength: 4)
            if copied {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(p.ok).transition(.scale.combined(with: .opacity))
            } else if hover {
                HStack(spacing: 3) {
                    mini(item.pinned ? "pin.slash.fill" : "pin.fill") { clip.togglePin(item.id) }
                    mini("xmark") { withAnimation(D.snappy) { clip.delete(item.id) } }
                }
            } else if item.pinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(D.amber).rotationEffect(.degrees(30))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? p.ink4 : p.track)
        }
        .rotationEffect(.degrees(hover ? 0 : (Double(abs(item.id.hashValue % 7)) - 3) * 0.15))
        .scaleEffect(copied ? 0.96 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            clip.copy(item)
            withAnimation(D.snappy) { copied = true }
            (NSApp.delegate as? AppDelegate)?.notch.cheer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(D.springOut) { copied = false } }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }

    private var icon: String {
        guard let t = item.text else { return "doc.text" }
        if t.hasPrefix("http") { return "link" }
        if t.contains("{") || t.contains(";") || t.contains("func ") { return "chevron.left.forwardslash.chevron.right" }
        return "text.alignleft"
    }

    private func mini(_ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: s).font(.system(size: 8.5, weight: .bold)).foregroundStyle(D.p.ink2)
                .frame(width: 20, height: 20).background(Circle().fill(D.p.card)).contentShape(Circle())
        }.buttonStyle(PressScale())
    }

    private var meta: String {
        let when = Calendar.current.isDateInToday(item.createdAt) ? Fmt.hm(item.createdAt) : Fmt.dayShort(item.createdAt)
        var parts = [item.source ?? "—", when]
        if let size = item.imageSize { parts.insert(size, at: 1) }
        return parts.joined(separator: " · ")
    }
}

private struct ClipThumb: View {
    let file: String?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(D.p.ink4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onAppear {
            if image == nil, let file { image = NSImage(contentsOf: ClipboardStore.imageURL(file)) }
        }
    }
}
