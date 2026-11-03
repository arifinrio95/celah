import SwiftUI
import UniformTypeIdentifiers

/// Storage inside Resources: the disk at a glance, then Clean up (what can go), Folders (where it went) and Files
/// (the biggest single files). Nothing is deleted: what you pick goes to the Trash after a second click, and
/// `StorageGuard` has the last word.
struct StorageView: View {
    @EnvironmentObject var store: StorageStore
    @AppStorage("storage.view") private var view = "clean"

    var body: some View {
        let p = D.p
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                diskBar
                Spacer(minLength: 8)
                if store.scanned {
                    HStack(spacing: 3) {
                        sub("Clean up", "sparkles", "clean")
                        sub("Folders", "folder", "folders")
                        sub("Files", "doc", "files")
                    }
                    .padding(2).background(Capsule().fill(p.track))
                }
                if store.isScanning {
                    Pill(symbol: "stop.fill", text: "Stop") { store.cancel() }
                } else {
                    Pill(symbol: "arrow.clockwise", text: store.scanned ? "Rescan" : "Scan", on: !store.scanned, tint: p.ink) { store.scan() }
                        .disabled(store.cleaning)
                }
            }
            if let n = store.notice {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(p.ok)
                    Text(n).lineLimit(2)
                    Spacer()
                    Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(p.ink3)
                }
                .font(D.rounded(11, .semibold)).foregroundStyle(p.ink2)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.ok.opacity(0.12)))
            }
            switch store.phase {
            case .idle: intro
            case .scanning(let files, let bytes, let at): scanning(files, bytes, at)
            case .done:
                switch forcedView ?? view {
                case "folders": FolderBrowser()
                case "files": BigFiles()
                default: CleanUp()
                }
            }
        }
    }

    /// Debug aid for snapshots: CELAH_STORAGE_VIEW=clean|folders|files.
    private var forcedView: String? { ProcessInfo.processInfo.environment["CELAH_STORAGE_VIEW"] }

    private var diskBar: some View {
        let p = D.p, d = store.disk
        let f = d.total > 0 ? Double(d.used) / Double(d.total) : 0
        return HStack(spacing: 10) {
            Image(systemName: "internaldrive.fill").font(.system(size: 13)).foregroundStyle(p.ink3)
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.track)
                        Capsule().fill(f > 0.9 ? p.danger : SystemView.diskColor).frame(width: g.size.width * f)
                    }
                }
                .frame(width: 150, height: 6)
                Text("\(Fmt.bytes(d.free)) free of \(Fmt.bytes(d.total))").font(D.rounded(10.5, .semibold)).foregroundStyle(p.ink3).monospacedDigit()
            }
        }
    }

    private func sub(_ title: String, _ symbol: String, _ key: String) -> some View {
        let p = D.p, on = view == key
        return Button { withAnimation(D.snappy) { view = key } } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                Text(title).font(D.rounded(10.5, .bold))
            }
            .foregroundStyle(on ? (p.dark ? Color.black : Color.white) : p.ink3)
            .padding(.horizontal, 9).frame(height: 22)
            .background { if on { Capsule().fill(p.ink) } }
            .contentShape(Capsule())
        }.buttonStyle(PressScale())
    }

    private var intro: some View {
        let p = D.p
        return HStack(spacing: 22) {
            ZStack {
                Circle().fill(SystemView.diskColor.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: "magnifyingglass").font(.system(size: 34, weight: .semibold)).foregroundStyle(SystemView.diskColor)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("What's filling your Mac?").font(D.serif(19).italic()).foregroundStyle(p.ink)
                Text("Scanning only reads your home folder: the biggest folders and files, and what can safely go. Nothing is touched until you pick it and confirm, and even then it only goes to the Trash.")
                    .font(D.rounded(12)).foregroundStyle(p.ink2).fixedSize(horizontal: false, vertical: true)
                Text("Takes about a minute. macOS may ask once to let Celah read Desktop, Documents and Downloads.")
                    .font(D.rounded(10.5)).foregroundStyle(p.ink3).fixedSize(horizontal: false, vertical: true)
                Pill(symbol: "magnifyingglass", text: "Scan my Mac", on: true, tint: p.ink) { store.scan() }
                    .padding(.top, 2)
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scanning(_ files: Int, _ bytes: Int64, _ at: String) -> some View {
        let p = D.p
        return VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("\(files.formatted()) files · \(Fmt.bytes(bytes))").font(D.rounded(15, .bold)).monospacedDigit().foregroundStyle(p.ink)
            Text(at.replacingOccurrences(of: store.home, with: "~")).font(D.mono(10.5)).foregroundStyle(p.ink3)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Clean up

private struct CleanUp: View {
    @EnvironmentObject var store: StorageStore
    @State private var open: String?            // a review suggestion whose items are showing
    @State private var confirm = false

    var body: some View {
        let p = D.p
        let safe = store.suggestions.filter { $0.tier == .safe }
        let review = store.suggestions.filter { $0.tier == .review }
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                column("SAFE TO CLEAN", "checkmark.shield.fill", p.ok, "Rebuilds by itself", safe)
                if let id = open, let s = store.suggestions.first(where: { $0.id == id }) {
                    ItemList(suggestion: s) { withAnimation(D.snappy) { open = nil } }
                } else {
                    column("REVIEW FIRST", "eye.fill", D.amber, "Yours. Tick only what you're sure of", review)
                }
            }
            footer
        }
    }

    private func column(_ title: String, _ symbol: String, _ c: Color, _ hint: String, _ list: [StorageStore.Suggestion]) -> some View {
        let p = D.p
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(c)
                Text(title).font(D.label(9)).tracking(1.1).foregroundStyle(p.ink2)
                Text("· " + hint).font(D.rounded(10, .medium)).foregroundStyle(p.ink3).lineLimit(1)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    if list.isEmpty {
                        Text("Nothing here. Nice and tidy.").font(D.rounded(11.5)).foregroundStyle(p.ink3)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    ForEach(list) { s in row(s) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ s: StorageStore.Suggestion) -> some View {
        let p = D.p
        let ids = Set(s.items.map(\.id))
        let n = ids.intersection(store.picked).count
        let state: Check.State = n == 0 ? .off : (n == ids.count ? .on : .some)
        return HStack(spacing: 9) {
            Check(state: state) { store.toggle(s) }
            Image(systemName: s.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.ink2).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(D.rounded(12, .semibold)).foregroundStyle(p.ink).lineLimit(1)
                Text(s.detail).font(D.rounded(10)).foregroundStyle(p.ink3).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Fmt.bytes(s.bytes)).font(D.rounded(12, .bold)).monospacedDigit().foregroundStyle(p.ink)
            Button { withAnimation(D.snappy) { open = s.id } } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(p.ink3)
                    .frame(width: 20, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("See the \(s.items.count) items")
        }
        .padding(.horizontal, 9).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(p.track))
    }

    private var footer: some View {
        let p = D.p
        let total = store.pickedBytes
        return HStack(spacing: 10) {
            Group {
                if total == 0 { Text("Tick what you want gone. Nothing is deleted: it all goes to the Trash.") }
                else { Text("Moves \(Fmt.bytes(total)) to the Trash. You can put anything back; empty the Trash yourself to free the space.") }
            }
            .font(D.rounded(11, .medium)).foregroundStyle(p.ink3).lineLimit(1)
            Spacer()
            if store.cleaning {
                ProgressView().controlSize(.small)
                Text("Cleaning…").font(D.rounded(11.5, .semibold)).foregroundStyle(p.ink2)
            } else {
                Button {
                    if confirm { confirm = false; store.clean() }
                    else {
                        withAnimation(D.snappy) { confirm = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { confirm = false } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: confirm ? "exclamationmark.triangle.fill" : "sparkles").font(.system(size: 11, weight: .bold))
                        Text(confirm ? "Sure? Move \(Fmt.bytes(total)) to Trash" : "Deep Clean · \(Fmt.bytes(total))").font(D.rounded(12, .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(Capsule().fill(confirm ? p.danger : (total > 0 ? p.ok : p.ink4)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .disabled(total == 0)
                .help("Click, then click again to confirm")
            }
        }
    }
}

/// The items inside one suggestion, each with its own tick, so a review can be precise.
private struct ItemList: View {
    @EnvironmentObject var store: StorageStore
    let suggestion: StorageStore.Suggestion
    let back: () -> Void

    var body: some View {
        let p = D.p
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: back) {
                    HStack(spacing: 4) { Image(systemName: "chevron.left"); Text(suggestion.title) }
                        .font(D.rounded(11, .bold)).foregroundStyle(p.ink2)
                }.buttonStyle(.plain)
                Spacer()
                Text("\(suggestion.items.count) items · \(Fmt.bytes(suggestion.bytes))").font(D.rounded(10.5, .semibold)).foregroundStyle(p.ink3)
            }
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    ForEach(suggestion.items) { item in
                        HStack(spacing: 8) {
                            Check(state: store.picked.contains(item.id) ? .on : .off) {
                                if store.picked.contains(item.id) { store.picked.remove(item.id) } else { store.picked.insert(item.id) }
                            }
                            FileIcon(url: item.url)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.name).font(D.rounded(11.5, .semibold)).foregroundStyle(p.ink).lineLimit(1).truncationMode(.middle)
                                Text(where_(item)).font(D.rounded(9.5)).foregroundStyle(p.ink3).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 4)
                            Text(Fmt.bytes(item.bytes)).font(D.rounded(11, .bold)).monospacedDigit().foregroundStyle(p.ink2)
                            RevealButton { store.reveal(item) }
                        }
                        .padding(.horizontal, 8).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.track))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func where_(_ item: StorageStore.Item) -> String {
        let folder = item.url.deletingLastPathComponent().path.replacingOccurrences(of: store.home, with: "~")
        guard let d = item.opened else { return folder }
        return "\(folder) · opened \(d.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - Folders

private struct FolderBrowser: View {
    @EnvironmentObject var store: StorageStore
    @State private var path: String = NSHomeDirectory()
    @State private var rows: [StorageStore.Item] = []
    @State private var loading = false

    var body: some View {
        let p = D.p
        let parent = store.dirSizes[path] ?? max(1, rows.map(\.bytes).reduce(0, +))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { i, c in
                    if i > 0 { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(p.ink4) }
                    Button { path = c.path } label: {
                        Text(c.name).font(D.rounded(11, i == crumbs.count - 1 ? .bold : .semibold))
                            .foregroundStyle(i == crumbs.count - 1 ? p.ink : p.ink3)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text(Fmt.bytes(store.dirSizes[path] ?? -1)).font(D.rounded(11, .bold)).monospacedDigit().foregroundStyle(p.ink2)
            }
            if loading && rows.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(rows) { item in
                            EntryRow(item: item, share: Double(max(0, item.bytes)) / Double(max(1, parent)),
                                     open: item.url.hasDirectoryPath && item.bytes >= 0 ? { path = item.url.path } : nil,
                                     onTrash: { rows.removeAll { $0.id == item.id } })
                        }
                    }
                }
            }
        }
        .task(id: path) { await load() }
    }

    private var crumbs: [(name: String, path: String)] {
        let home = store.home
        guard path.hasPrefix(home) else { return [(path, path)] }
        var out: [(String, String)] = [("Home", home)]
        var cur = home
        for part in path.dropFirst(home.count).split(separator: "/") {
            cur += "/" + part
            out.append((String(part), cur))
        }
        return out.count > 5 ? [out[0], ("…", out[out.count - 4].1)] + out.suffix(3) : out
    }

    /// Lists off the main thread: reading Desktop, Documents or Downloads can wait on a macOS permission prompt.
    private func load() async {
        loading = true
        let p = path, sizes = store.dirSizes
        let list = await Task.detached(priority: .userInitiated) { StorageStore.children(of: p, sizes: sizes) }.value
        if p == path { rows = list; loading = false }
    }
}

// MARK: - Files

private struct BigFiles: View {
    @EnvironmentObject var store: StorageStore

    var body: some View {
        let p = D.p
        let top = store.topFiles.first?.bytes ?? 1
        VStack(alignment: .leading, spacing: 6) {
            Text("THE BIGGEST FILES IN YOUR HOME FOLDER").font(D.label(9)).tracking(1.1).foregroundStyle(p.ink3)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    ForEach(store.topFiles) { item in
                        EntryRow(item: item, share: Double(item.bytes) / Double(max(1, top)), showFolder: true)
                    }
                }
            }
        }
    }
}

// MARK: - shared rows

/// A file or folder with its size, a reveal button, and a two-step Trash (or a lock that says why not).
private struct EntryRow: View {
    @EnvironmentObject var store: StorageStore
    let item: StorageStore.Item
    let share: Double
    var showFolder = false
    var open: (() -> Void)? = nil
    var onTrash: (() -> Void)? = nil
    @State private var confirm = false
    @State private var hover = false

    var body: some View {
        let p = D.p
        let why = StorageGuard.reason(item.url)
        HStack(spacing: 9) {
            FileIcon(url: item.url)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(D.rounded(11.5, .semibold)).foregroundStyle(p.ink).lineLimit(1).truncationMode(.middle)
                if showFolder {
                    Text(subtitle).font(D.rounded(9.5)).foregroundStyle(p.ink3).lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(width: 250, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(SystemView.diskColor.opacity(0.14))
                    Capsule().fill(SystemView.diskColor).frame(width: max(2, g.size.width * min(1, share)))
                }
            }
            .frame(height: 5)
            Text(item.bytes < 0 ? "not read" : Fmt.bytes(item.bytes)).font(D.rounded(11, .bold)).monospacedDigit()
                .foregroundStyle(item.bytes < 0 ? p.ink4 : p.ink2).frame(width: 70, alignment: .trailing)
            RevealButton { store.reveal(item) }
            if let why {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(p.ink4).frame(width: 64)
                    .help("Celah won't remove this: \(why).")
            } else {
                Button {
                    if confirm { confirm = false; store.trash(item); onTrash?() }
                    else {
                        withAnimation(D.snappy) { confirm = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { confirm = false } }
                    }
                } label: {
                    Text(confirm ? "Sure?" : "Trash").font(D.rounded(10, .bold))
                        .foregroundStyle(confirm ? Color.white : p.danger)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Capsule().fill(confirm ? p.danger : p.danger.opacity(0.10)))
                }
                .buttonStyle(PressScale()).frame(width: 64)
                .help("Move to the Trash. You can put it back from there.")
            }
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(p.ink3)
                .frame(width: 10).opacity(open == nil ? 0 : 1)
        }
        .padding(.horizontal, 9).frame(height: showFolder ? 36 : 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover && open != nil ? p.ink4.opacity(0.5) : p.track))
        .contentShape(Rectangle())
        .onTapGesture { open?() }
        .onHover { hover = $0 }
    }

    private var subtitle: String {
        let folder = item.url.deletingLastPathComponent().path.replacingOccurrences(of: store.home, with: "~")
        guard let d = item.opened else { return folder }
        return "\(folder) · opened \(d.formatted(.relative(presentation: .named)))"
    }
}

private struct RevealButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .bold)).foregroundStyle(D.p.ink3)
                .frame(width: 20, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("Show in Finder")
    }
}

private struct FileIcon: View {
    let url: URL
    var body: some View {
        // by type, not by file: reading a file's own icon can stall on a privacy prompt
        let type: UTType = url.hasDirectoryPath ? (url.pathExtension == "app" ? .applicationBundle : .folder)
                                               : (UTType(filenameExtension: url.pathExtension) ?? .data)
        Image(nsImage: NSWorkspace.shared.icon(for: type)).resizable().interpolation(.high).frame(width: 18, height: 18)
    }
}

/// A tick box with an in-between state for a group that's partly picked.
struct Check: View {
    enum State { case off, some, on }
    let state: State
    let action: () -> Void
    var body: some View {
        let p = D.p
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(state == .off ? Color.clear : p.ok)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(state == .off ? p.ink4 : p.ok, lineWidth: 1.5))
                if state != .off {
                    Image(systemName: state == .on ? "checkmark" : "minus").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
