import SwiftUI

/// Mushaf Mode: a big reading window. Surah list on the side, one verse large in the middle (or the whole
/// surah as a scroll), adjustable script size, keyboard navigation. Shares its position with the notch card.
struct QuranReader: View {
    @EnvironmentObject var quran: QuranStore
    @EnvironmentObject var settings: AppSettings
    @AppStorage("quran.reader.size") private var arabicSize: Double = 42
    @AppStorage("quran.reader.translation") private var showTranslation = true
    @AppStorage("quran.reader.mode") private var mode = "ayah"
    @AppStorage("quran.reader.sidebar") private var sidebar = true
    @State private var query = ""
    @State private var forward = true
    @FocusState private var focused: Bool

    private var dark: Bool { settings.look == "ink" }
    private var paper: [Color] { dark ? [Color(hex: 0x141A17), Color(hex: 0x0E1110)] : [Color(hex: 0xF8F1E1), Color(hex: 0xEFE3C7)] }
    private var ink: Color { dark ? Color(hex: 0xF3EEE3) : Color(hex: 0x2A2117) }
    private var ink2: Color { ink.opacity(0.66) }
    private var ink3: Color { ink.opacity(0.42) }
    private var hair: Color { ink.opacity(0.10) }
    private let green = Color(hex: 0x2F8F6B)
    private let gold = Color(hex: 0xB8862B)

    var body: some View {
        HStack(spacing: 0) {
            if sidebar { surahList.frame(width: 250).transition(.move(edge: .leading).combined(with: .opacity)) }
            VStack(spacing: 0) {
                topBar
                if let ay = quran.current, let s = quran.currentSurah {
                    if mode == "ayah" { ayahView(ay, s) } else { surahScroll(s) }
                } else {
                    Spacer(); Text("Opening the mushaf…").font(D.serif(18).italic()).foregroundStyle(ink3); Spacer()
                }
                bottomBar
            }
        }
        .background {
            ZStack {
                LinearGradient(colors: paper, startPoint: .top, endPoint: .bottom)
                StarLattice(cell: 54).stroke((dark ? Color(hex: 0x7FD1AE) : Color(hex: 0x8A6A2E)).opacity(dark ? 0.05 : 0.07), lineWidth: 0.8)
                RadialGradient(colors: [.clear, .black.opacity(dark ? 0.35 : 0.08)], center: .center, startRadius: 300, endRadius: 900)
            }
            .ignoresSafeArea()
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.rightArrow) { go(+1); return .handled }
        .onKeyPress(.leftArrow) { go(-1); return .handled }
        .onKeyPress(.space) { go(+1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "+=")) { _ in arabicSize = min(72, arabicSize + 4); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "-")) { _ in arabicSize = max(24, arabicSize - 4); return .handled }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sidebar)
        .preferredColorScheme(dark ? .dark : .light)
    }

    private func go(_ d: Int) {
        forward = d > 0
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { d > 0 ? quran.next() : quran.prev() }
    }

    // MARK: - Sidebar

    private var surahList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .bold)).foregroundStyle(ink3)
                TextField("Find a surah", text: $query).textFieldStyle(.plain).font(D.rounded(13, .medium)).foregroundStyle(ink)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(Capsule().fill(ink.opacity(0.06)))
            .padding(.horizontal, 14).padding(.top, 44).padding(.bottom, 10)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered, id: \.n) { s in
                            let on = s.n == quran.current?.surah
                            Button { forward = true; withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { quran.jump(toSurah: s.n) } } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Image(systemName: "seal.fill").font(.system(size: 26)).foregroundStyle(on ? green : ink.opacity(0.07))
                                        Text(verbatim: "\(s.n)").font(D.rounded(10, .heavy)).foregroundStyle(on ? .white : ink2)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.latin).font(D.rounded(13, on ? .bold : .semibold)).foregroundStyle(ink).lineLimit(1)
                                        Text("\(s.en) · \(s.count)").font(D.rounded(10.5, .medium)).foregroundStyle(ink3).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Text(shortArabic(s.ar)).font(.custom("Amiri Quran", size: 17)).foregroundStyle(on ? green : ink2)
                                        .lineLimit(1).fixedSize()
                                }
                                .padding(.horizontal, 10).frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? green.opacity(0.10) : .clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(s.n)
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 16)
                }
                .onAppear { if let n = quran.current?.surah { proxy.scrollTo(n, anchor: .center) } }
            }
        }
        .background(ink.opacity(dark ? 0.03 : 0.025))
        .overlay(alignment: .trailing) { Rectangle().fill(hair).frame(width: 1) }
    }

    /// "سُورَةُ ٱلْبَقَرَةِ" → "ٱلْبَقَرَةِ": the list already says it is a surah.
    private func shortArabic(_ ar: String) -> String {
        let parts = ar.split(separator: " ", maxSplits: 1)
        return parts.count == 2 && parts[0].hasPrefix("سُ") ? String(parts[1]) : ar
    }

    private var filtered: [QuranStore.Surah] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return quran.surahs }
        return quran.surahs.filter { $0.latin.lowercased().contains(q) || $0.en.lowercased().contains(q) || "\($0.n)" == q || $0.ar.contains(q) }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack(spacing: 10) {
            barButton(sidebar ? "sidebar.left" : "sidebar.left", on: sidebar) { sidebar.toggle() }
            Spacer()
            if let s = quran.currentSurah {
                VStack(spacing: 1) {
                    Text(s.ar).font(.custom("Amiri Quran", size: 26)).foregroundStyle(ink)
                    Text("\(s.latin) · \(s.en) · \(s.type.capitalized) · \(s.count) ayat").font(D.rounded(11.5, .semibold)).foregroundStyle(ink3)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                segment("Ayah", "text.alignright", "ayah")
                segment("Surah", "scroll", "surah")
            }
            .padding(3).background(Capsule().fill(ink.opacity(0.06)))
        }
        .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 8)
    }

    private func segment(_ title: String, _ icon: String, _ value: String) -> some View {
        let on = mode == value
        return Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = value } } label: {
            Label(title, systemImage: icon).font(D.rounded(12, .bold))
                .foregroundStyle(on ? .white : ink2)
                .padding(.horizontal, 12).frame(height: 26)
                .background { if on { Capsule().fill(green) } }
                .contentShape(Capsule())
        }.buttonStyle(PressScale())
    }

    private func barButton(_ icon: String, on: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(on ? green : ink2)
                .frame(width: 32, height: 30).background(RoundedRectangle(cornerRadius: 9).fill(ink.opacity(0.06))).contentShape(Rectangle())
        }.buttonStyle(PressScale())
    }

    private var bottomBar: some View {
        let range = quran.current.map { quran.range(ofSurah: $0.surah) } ?? 0..<1
        let inSurah = Double(quran.index - range.lowerBound + 1) / Double(max(1, range.count))
        return HStack(spacing: 14) {
            HStack(spacing: 6) {
                barButton("textformat.size.smaller") { arabicSize = max(24, arabicSize - 4) }
                barButton("textformat.size.larger") { arabicSize = min(72, arabicSize + 4) }
                barButton("character.book.closed", on: showTranslation) { withAnimation(.easeInOut(duration: 0.25)) { showTranslation.toggle() } }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    if let a = quran.current { Text("\(a.surah):\(a.number)").font(D.rounded(12, .bold)).monospacedDigit().foregroundStyle(ink2) }
                    Spacer()
                    Text(verbatim: "\(quran.index + 1) / \(quran.count)").font(D.rounded(11, .semibold)).monospacedDigit().foregroundStyle(ink3)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ink.opacity(0.08))
                        Capsule().fill(LinearGradient(colors: [green, gold], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, g.size.width * inSurah))
                    }
                }
                .frame(height: 5)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: inSurah)
            }
            HStack(spacing: 8) {
                navButton("chevron.left", filled: false) { go(-1) }
                navButton("chevron.right", filled: true) { go(+1) }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.ultraThinMaterial.opacity(0.0001))
        .overlay(alignment: .top) { Rectangle().fill(hair).frame(height: 1) }
    }

    private func navButton(_ icon: String, filled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
                .foregroundStyle(filled ? .white : ink2)
                .frame(width: 46, height: 46)
                .background(Circle().fill(filled ? green : ink.opacity(0.07)))
                .contentShape(Circle())
        }.buttonStyle(PressScale())
    }

    // MARK: - Reading

    private func ayahView(_ ay: QuranStore.Ayah, _ s: QuranStore.Surah) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 26) {
                if ay.number == 1 && s.n != 1 && s.n != 9 { bismillah }
                Text(ay.arabic + " " + marker(ay.number))
                    .font(.custom("Amiri Quran", size: arabicSize))
                    .foregroundStyle(ink)
                    .lineSpacing(arabicSize * 0.55)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: 860)
                    .fixedSize(horizontal: false, vertical: true)
                if showTranslation {
                    VStack(spacing: 10) {
                        Ornament(color: gold)
                        Text(ay.translation)
                            .font(D.serif(max(15, arabicSize * 0.42)).italic())
                            .foregroundStyle(ink2)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .frame(maxWidth: 720)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 48).padding(.vertical, 40)
            .frame(maxWidth: .infinity)
            .id(quran.index)
            .transition(.asymmetric(insertion: .pageTurn(forward ? 1 : -1), removal: .opacity.animation(.easeOut(duration: 0.15))))
        }
        .frame(maxHeight: .infinity)
    }

    private func surahScroll(_ s: QuranStore.Surah) -> some View {
        let r = quran.range(ofSurah: s.n)
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if s.n != 1 && s.n != 9 { bismillah.padding(.vertical, 24) }
                    ForEach(Array(r), id: \.self) { i in
                        let a = quran.ayahs[i]
                        let on = i == quran.index
                        VStack(alignment: .trailing, spacing: 10) {
                            Text(a.arabic + " " + marker(a.number))
                                .font(.custom("Amiri Quran", size: arabicSize * 0.8))
                                .foregroundStyle(ink)
                                .lineSpacing(arabicSize * 0.4)
                                .multilineTextAlignment(.trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .fixedSize(horizontal: false, vertical: true)
                            if showTranslation {
                                Text("\(a.number). \(a.translation)")
                                    .font(D.serif(15).italic()).foregroundStyle(ink2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 22).padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? green.opacity(dark ? 0.16 : 0.09) : .clear))
                        .overlay(alignment: .leading) {
                            if on { Capsule().fill(green).frame(width: 4).padding(.vertical, 16) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { quran.index = i } }
                        .id(i)
                    }
                }
                .padding(.horizontal, 40).padding(.bottom, 40)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .onAppear { proxy.scrollTo(quran.index, anchor: .center) }
            .onChange(of: quran.index) { _, i in withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(i, anchor: .center) } }
        }
        .frame(maxHeight: .infinity)
    }

    private var bismillah: some View {
        Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
            .font(.custom("Amiri Quran", size: max(22, arabicSize * 0.62)))
            .foregroundStyle(green)
            .environment(\.layoutDirection, .rightToLeft)
    }

    /// End-of-ayah sign with the number in Arabic-Indic digits.
    private func marker(_ n: Int) -> String {
        let digits = String(n).map { c -> Character in
            guard let v = c.wholeNumberValue else { return c }
            return Character(UnicodeScalar(0x0660 + v)!)
        }
        return "\u{06DD}" + String(digits)
    }
}

/// A small divider ornament: line, diamond, line.
struct Ornament: View {
    let color: Color
    var body: some View {
        HStack(spacing: 10) {
            Capsule().fill(LinearGradient(colors: [.clear, color.opacity(0.7)], startPoint: .leading, endPoint: .trailing)).frame(width: 90, height: 1)
            Image(systemName: "sparkle").font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            Capsule().fill(LinearGradient(colors: [color.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)).frame(width: 90, height: 1)
        }
    }
}
