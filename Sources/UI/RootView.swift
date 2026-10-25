import SwiftUI

/// Window content. Closed: the hardware notch, plus wings when something is live, plus a curious creature
/// that peeks out when the cursor comes near. Open: the notch stretches into a black lip and a paper tray
/// is printed out of it, cards dealt onto it one by one.
struct NotchRootView: View {
    @ObservedObject var ctl: NotchController
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let _ = { D.p = settings.look == "ink" ? .ink : .porcelain }()
        let open = ctl.isExpanded
        let H = ctl.geometry.notchHeight
        let peek = ctl.geometry.hasNotch ? ctl.proximity : 0
        let chin = open ? ctl.chinDepth : peek * 18
        let chinW = open ? ctl.chinWidth : 60
        let lipW = open ? ctl.lipWidth : ctl.collapsedWidth
        let faceCenter = CGPoint(x: ctl.geometry.centerX, y: ctl.geometry.top - H - chin / 2)

        ZStack(alignment: .top) {
            Color.clear

            TrayView(ctl: ctl)
                .padding(.horizontal, ctl.shadowPad)
                .padding(.bottom, ctl.shadowPad)
                .mask(alignment: .top) {
                    Rectangle().frame(height: open ? ctl.trayHeight + ctl.shadowPad + 20 : 0)
                }
                .offset(y: H - ctl.trayOverlap + (open ? 0 : -26))
                .rotation3DEffect(.degrees(open ? 0 : 24), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.45)
                .opacity(open ? 1 : 0)
                .allowsHitTesting(open)
                .animation(open ? .spring(response: 0.5, dampingFraction: 0.8).delay(0.05) : .easeIn(duration: 0.16), value: open)

            LipShape(ear: open ? ctl.ear : 0, radius: open ? H / 2 : ctl.collapsedRadius,
                     chinWidth: chinW, chinDepth: chin, lipHeight: H)
                .fill(D.lip)
                .frame(width: lipW, height: H)
                .opacity(open || ctl.drawsCollapsed || chin > 0.5 ? 1 : 0)
                .animation(D.springIn, value: open)
                .animation(.spring(response: 0.36, dampingFraction: 0.86), value: lipW)

            LipContent(ctl: ctl)
                .frame(width: ctl.lipWidth, height: H)
                .opacity(open ? 1 : 0)
                .animation(open ? D.springIn.delay(0.12) : .easeIn(duration: 0.1), value: open)
                .allowsHitTesting(false)

            CollapsedView(ctl: ctl)
                .frame(width: ctl.collapsedWidth, height: H)
                .opacity(open ? 0 : 1)
                .allowsHitTesting(false)
            if !open && ctl.opensOnClick {
                Color.black.opacity(0.001)
                    .frame(width: ctl.collapsedWidth + 12, height: H + chin + 3)
                    .contentShape(Rectangle())
                    .onTapGesture { ctl.expand() }
            }

            // the creature, in its chin
            CreatureFace(mood: ctl.mood, look: lookVector(from: faceCenter, to: ctl.mouse),
                         scale: open ? 1 : 0.78, awake: open || peek > 0.2)
                .offset(y: H + chin / 2 - (open ? 12 : 10))
                .opacity(open ? 1 : Double(max(0, (peek - 0.35) / 0.4)))
                .animation(D.springIn, value: open)
            if open {
                Color.clear
                    .frame(width: ctl.chinWidth, height: ctl.chinDepth)
                    .contentShape(Rectangle())
                    .offset(y: H)
                    .onTapGesture { ctl.poke() }
            }
            if let q = ctl.quip, open {
                QuipBubble(text: q)
                    .offset(y: H + ctl.chinDepth + 6)
                    .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .frame(width: ctl.windowSize.width, height: ctl.windowSize.height, alignment: .top)
        .id(settings.look)
    }
}

/// The paper itself: warm gradient, grain, a shadow cast by the lip, then the board.
struct TrayView: View {
    @ObservedObject var ctl: NotchController

    var body: some View {
        let p = D.p
        let shape = UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 30, bottomTrailingRadius: 30, topTrailingRadius: 6, style: .continuous)
        BoardView(ctl: ctl)
            .padding(.horizontal, 12)
            .padding(.top, ctl.trayOverlap + 4)
            .padding(.bottom, 12)
            .frame(width: ctl.trayWidth, height: ctl.trayHeight)
            .background {
                ZStack(alignment: .top) {
                    shape.fill(LinearGradient(colors: [p.trayTop, p.trayBottom], startPoint: .top, endPoint: .bottom))
                    Grain(opacity: p.dark ? 0.06 : 0.07).clipShape(shape)
                    LinearGradient(colors: [Color.black.opacity(p.dark ? 0.5 : 0.22), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 22).clipShape(shape)
                    shape.strokeBorder(p.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(p.dark ? 0.55 : 0.28), radius: 26, y: 16)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            }
    }
}

/// Inside the lip, well clear of the camera: a wordmark on the left, the time on the right.
struct LipContent: View {
    @ObservedObject var ctl: NotchController
    @EnvironmentObject var clock: Clock

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(D.amber).frame(width: 5, height: 5)
                Text("celah").font(D.serif(15, .medium).italic()).foregroundStyle(.white)
            }
            Spacer(minLength: ctl.geometry.notchWidth + 40)
            Text(Fmt.hm(clock.now)).font(D.rounded(13, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.78))
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 2)
    }
}

struct QuipBubble: View {
    let text: String
    var body: some View {
        let p = D.p
        VStack(spacing: -1) {
            Triangle().fill(p.dark ? Color(hex: 0x2A2A31) : .white).frame(width: 12, height: 6)
            Text(text)
                .font(D.rounded(12, .semibold))
                .foregroundStyle(p.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(p.dark ? Color(hex: 0x2A2A31) : .white))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        }
        .fixedSize()
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath(); return p
    }
}

/// What peeks out beside the physical notch while closed.
struct CollapsedView: View {
    @ObservedObject var ctl: NotchController
    @EnvironmentObject var music: MusicBridge
    @EnvironmentObject var prayer: PrayerService
    @EnvironmentObject var clock: Clock
    @EnvironmentObject var awake: KeepAwake
    @EnvironmentObject var recorder: MeetingRecorder

    var body: some View {
        let wing = (ctl.collapsedWidth - ctl.geometry.notchWidth) / 2
        HStack(spacing: 0) {
            leftWing.frame(width: wing, height: ctl.collapsedHeight).padding(.leading, 6)
            Spacer().frame(width: ctl.geometry.notchWidth - 12)
            rightWing.frame(width: wing, height: ctl.collapsedHeight).padding(.trailing, 6)
        }
        .frame(width: ctl.collapsedWidth)
    }

    @ViewBuilder private var leftWing: some View {
        switch ctl.wing {
        case .recording:
            TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                let k = 0.6 + 0.4 * abs(sin(tl.date.timeIntervalSinceReferenceDate * 3))
                Circle().fill(D.p.danger).frame(width: 9, height: 9).scaleEffect(k)
                    .shadow(color: Color.red.opacity(0.8), radius: 5 * k)
            }
        case .awake:
            SteamingCup(size: 16, live: true)
        case .music:
            Vinyl(art: music.artwork, size: 22, spinning: music.now?.isPlaying == true)
        case .prayer:
            Image(systemName: "moon.stars.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(D.amber)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var rightWing: some View {
        switch ctl.wing {
        case .recording:
            Text(Fmt.short(clock.now.timeIntervalSince(recorder.startedAt ?? clock.now)))
                .font(D.rounded(12, .bold)).monospacedDigit().foregroundStyle(.white)
        case .awake:
            Text(awake.endsAt.map { Fmt.short($0.timeIntervalSince(clock.now)) } ?? "∞")
                .font(D.rounded(12, .bold)).monospacedDigit().foregroundStyle(.white)
        case .music:
            Equalizer(playing: music.now?.isPlaying == true)
        case .prayer:
            if let next = prayer.next(at: clock.now) {
                Text(Fmt.short(next.date.timeIntervalSince(clock.now)))
                    .font(D.rounded(12, .bold)).monospacedDigit().foregroundStyle(.white)
            }
        case .none:
            EmptyView()
        }
    }
}

struct Equalizer: View {
    let playing: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (2.3 + Double(i) * 0.6) + Double(i) * 1.1
                    let h = playing ? 4 + 11 * abs(sin(phase)) : 3
                    Capsule().fill(D.amber).frame(width: 2.6, height: h)
                }
            }
            .frame(height: 16)
        }
    }
}

/// A record with the album art as its label. Spins at 33⅓ while playing.
struct Vinyl: View {
    let art: NSImage?
    var size: CGFloat
    var spinning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 40, paused: !spinning)) { tl in
            let angle = spinning ? tl.date.timeIntervalSinceReferenceDate * 200 : 0
            ZStack {
                Circle().fill(Color(hex: 0x111113))
                Canvas { ctx, sz in
                    let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                    for i in 0..<Int(size / 7) {
                        let r = sz.width / 2 * (0.42 + CGFloat(i) * (0.55 / CGFloat(max(1, Int(size / 7)))))
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                   with: .color(.white.opacity(0.07)), lineWidth: 0.6)
                    }
                    // a light streak, so the spin reads
                    var s = Path(); s.move(to: c); s.addArc(center: c, radius: sz.width / 2, startAngle: .degrees(-20), endAngle: .degrees(10), clockwise: false); s.closeSubpath()
                    ctx.fill(s, with: .color(.white.opacity(0.06)))
                }
                Group {
                    if let art { Image(nsImage: art).resizable().aspectRatio(contentMode: .fill) } else { D.amber }
                }
                .frame(width: size * 0.4, height: size * 0.4).clipShape(Circle())
                Circle().fill(Color.black).frame(width: max(2, size * 0.05), height: max(2, size * 0.05))
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
        }
    }
}

/// A cup with steam that curls upward.
struct SteamingCup: View {
    var size: CGFloat = 16
    var live = true
    var coffee = true
    var color: Color = D.amber

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !live)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let s = sz.width / 16
                // steam
                if coffee {
                    for i in 0..<3 {
                        let x0 = (4.2 + Double(i) * 2.8) * s
                        var p = Path()
                        let ph = t * 2.2 + Double(i) * 1.7
                        p.move(to: CGPoint(x: x0, y: 7 * s))
                        for k in 1...8 {
                            let y = 7 * s - Double(k) * 0.85 * s
                            p.addLine(to: CGPoint(x: x0 + sin(ph + Double(k) * 0.9) * 0.9 * s, y: y))
                        }
                        let fade = 0.35 + 0.35 * sin(ph * 0.7)
                        ctx.stroke(p, with: .color(color.opacity(fade)), style: StrokeStyle(lineWidth: 1.1 * s, lineCap: .round))
                    }
                }
                // body
                var b = Path()
                b.move(to: CGPoint(x: 2.5 * s, y: 8 * s)); b.addLine(to: CGPoint(x: 12 * s, y: 8 * s))
                b.addLine(to: CGPoint(x: 11.2 * s, y: 13.4 * s))
                b.addQuadCurve(to: CGPoint(x: 3.3 * s, y: 13.4 * s), control: CGPoint(x: 7.25 * s, y: 15 * s))
                b.closeSubpath()
                ctx.fill(b, with: .color(color))
                ctx.stroke(Path(ellipseIn: CGRect(x: 10.6 * s, y: 8.9 * s, width: 3.6 * s, height: 3.4 * s)), with: .color(color), lineWidth: 1.3 * s)
                ctx.fill(Path(roundedRect: CGRect(x: 1.2 * s, y: 14.3 * s, width: 12.4 * s, height: 1.2 * s), cornerRadius: 0.6 * s), with: .color(color.opacity(0.8)))
            }
        }
        .frame(width: size, height: size)
    }
}
