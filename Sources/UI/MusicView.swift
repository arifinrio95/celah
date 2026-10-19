import SwiftUI

/// Music: the album sleeve, with the record sliding out of it while it plays.
struct MusicView: View {
    @EnvironmentObject var music: MusicBridge
    @EnvironmentObject var clock: Clock

    var body: some View {
        let player = music.now?.player ?? music.preferred ?? music.runningPlayers.first ?? .spotify
        let tint = ImageTint.average(music.artwork) ?? D.p.accent
        Card(title: "Music", glyph: "music.note", meta: player.displayName, metaAction: { Apps.open(bundleID: player.bundleID) },
             tint: tint, background: AnyView(wash(tint))) {
            Spacer(minLength: 8)
            if let np = music.now { playing(np) } else { idle }
            Spacer(minLength: 0)
        }
    }

    private func wash(_ tint: Color) -> some View {
        ZStack {
            if let art = music.artwork {
                Color.clear.overlay {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: 34).opacity(D.p.dark ? 0.35 : 0.22).scaleEffect(1.4)
                }
                .clipped()
            }
            LinearGradient(colors: [tint.opacity(D.p.dark ? 0.16 : 0.14), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func playing(_ np: MusicBridge.NowPlaying) -> some View {
        let p = D.p
        let pos = music.position(at: clock.now)
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 12) {
                Sleeve(art: music.artwork, playing: np.isPlaying, size: 80)
                    .onTapGesture { Apps.open(bundleID: np.player.bundleID) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(np.title).font(D.rounded(14, .bold)).foregroundStyle(p.ink).lineLimit(2)
                        .onTapGesture { Apps.open(bundleID: np.player.bundleID) }
                    Text(np.artist).font(D.rounded(11.5, .medium)).foregroundStyle(p.ink2).lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 8) {
                        Orb(symbol: "backward.fill", size: 26) { music.previous() }
                        Orb(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 32, filled: true) { music.playPause() }
                        Orb(symbol: "forward.fill", size: 26) { music.next() }
                    }
                }
                .frame(height: 80)
            }
            Groove(fraction: np.duration > 0 ? pos / np.duration : 0, elapsed: pos, total: np.duration) { f in
                music.seek(to: f * np.duration)
            }
        }
    }

    private var idle: some View {
        let p = D.p
        return HStack(spacing: 14) {
            Sleeve(art: nil, playing: false, size: 70).opacity(0.55)
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing spinning.").font(D.serif(15).italic()).foregroundStyle(p.ink2)
                HStack(spacing: 6) {
                    ForEach(MusicBridge.Player.allCases, id: \.self) { pl in
                        if let path = Apps.path(bundleID: pl.bundleID) {
                            Button { Apps.open(bundleID: pl.bundleID) } label: {
                                HStack(spacing: 5) {
                                    AppIconView(path: path, size: 14)
                                    Text(pl.displayName).font(D.rounded(11, .semibold)).foregroundStyle(p.ink2)
                                }
                                .padding(.horizontal, 8).frame(height: 24)
                                .background(Capsule().fill(p.track))
                                .contentShape(Capsule())
                            }.buttonStyle(PressScale())
                        }
                    }
                }
            }
        }
    }
}

/// Album art as a sleeve; the record peeks out to the right and spins while playing.
struct Sleeve: View {
    let art: NSImage?
    let playing: Bool
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Vinyl(art: art, size: size * 0.94, spinning: playing)
                .offset(x: playing ? size * 0.42 : size * 0.1)
                .animation(.spring(response: 0.7, dampingFraction: 0.72), value: playing)
            Group {
                if let art {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(colors: [D.p.ink4, D.p.track], startPoint: .top, endPoint: .bottom)
                        Image(systemName: "music.note").font(.system(size: size * 0.3, weight: .semibold)).foregroundStyle(D.p.ink3)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.25), radius: 8, x: 3, y: 4)
        }
        .frame(width: size * 1.42, height: size, alignment: .leading)
    }
}

/// Progress as a groove with a playhead you can drag or click.
struct Groove: View {
    let fraction: Double
    let elapsed: Double
    let total: Double
    let onSeek: (Double) -> Void
    @State private var hover = false

    var body: some View {
        let p = D.p
        HStack(spacing: 8) {
            Text(Fmt.clock(elapsed)).font(D.rounded(10, .semibold)).monospacedDigit().foregroundStyle(p.ink3)
            GeometryReader { g in
                let f = max(0, min(1, fraction))
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track).frame(height: 4)
                    Capsule().fill(p.ink).frame(width: f * g.size.width, height: 4)
                    Circle().fill(p.ink)
                        .frame(width: hover ? 12 : 8, height: hover ? 12 : 8)
                        .overlay(Circle().strokeBorder(p.card, lineWidth: 2))
                        .offset(x: f * g.size.width - (hover ? 6 : 4))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { v in onSeek(max(0, min(1, v.location.x / g.size.width))) })
            }
            .frame(height: 14)
            .onHover { hover = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
            Text(Fmt.clock(total)).font(D.rounded(10, .semibold)).monospacedDigit().foregroundStyle(p.ink3)
        }
    }
}
