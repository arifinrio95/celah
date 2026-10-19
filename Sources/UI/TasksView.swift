import SwiftUI

/// Tasks: project chips, four lanes as a segmented strip, a list where ticking a task pops it to the next lane.
struct TasksView: View {
    @ObservedObject var ctl: NotchController
    @EnvironmentObject var store: TaskStore
    @State private var newTitle = ""

    var body: some View {
        let p = D.p
        Card(title: "Tasks", glyph: "checklist", meta: store.activeCount > 0 ? "\(store.activeCount) active" : "Board",
             metaAction: { (NSApp.delegate as? AppDelegate)?.openTasks() }) {
            Spacer(minLength: 7)
            projectChips
            Spacer(minLength: 7)
            lanes
            Spacer(minLength: 5)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    let items = store.tasks(store.selectedStatus)
                    if items.isEmpty {
                        Text(emptyText).font(D.serif(13).italic()).foregroundStyle(p.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                    ForEach(items) { t in
                        TaskRow(task: t) { ctl.cheer() }
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
                .animation(D.snappy, value: store.tasks(store.selectedStatus).map(\.id))
            }
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 9, weight: .heavy)).foregroundStyle(p.ink3)
                    .frame(width: 18, height: 18).background(Circle().fill(p.track))
                TextField("", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(D.rounded(11.5, .medium))
                    .foregroundStyle(p.ink)
                    .overlay(alignment: .leading) {
                        if newTitle.isEmpty { Text("Add to \(store.selectedStatus.label)…").font(D.rounded(11.5, .medium)).foregroundStyle(p.ink3).allowsHitTesting(false) }
                    }
                    .onSubmit {
                        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        store.addTask(newTitle, status: store.selectedStatus); newTitle = ""; ctl.cheer()
                    }
            }
            .padding(.top, 4)
        }
    }

    private var emptyText: String {
        switch store.selectedStatus {
        case .backlog: return "Backlog is clear."
        case .todo: return "Nothing to do. Suspicious."
        case .inProgress: return "Nothing in flight."
        case .done: return "Nothing done yet. Yet."
        }
    }

    private var projectChips: some View {
        let p = D.p
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(store.projects) { pr in
                    let on = pr.id == store.selectedProjectID
                    Button { withAnimation(D.snappy) { store.selectedProjectID = pr.id } } label: {
                        Text(pr.name).font(D.rounded(10.5, .bold))
                            .foregroundStyle(on ? (p.dark ? Color.black : Color.white) : p.ink2)
                            .padding(.horizontal, 9).frame(height: 21)
                            .background(Capsule().fill(on ? p.ink : p.track))
                            .contentShape(Capsule())
                    }.buttonStyle(PressScale())
                }
            }
        }
        .frame(height: 21)
    }

    private var lanes: some View {
        let p = D.p
        return HStack(spacing: 3) {
            ForEach(TaskStatus.allCases) { s in
                let on = s == store.selectedStatus
                let n = store.count(s)
                Button { withAnimation(D.snappy) { store.selectedStatus = s } } label: {
                    HStack(spacing: 4) {
                        Text(s.short).font(D.label(8.5)).tracking(0.6)
                        if n > 0 {
                            Text(verbatim: "\(n)").font(D.rounded(9, .heavy)).monospacedDigit()
                                .padding(.horizontal, 4).frame(height: 13)
                                .background(Capsule().fill(on ? Color.white.opacity(0.28) : p.ink4))
                        }
                    }
                    .foregroundStyle(on ? Color.white : p.ink3)
                    .frame(maxWidth: .infinity).frame(height: 22)
                    .background { if on { Capsule().fill(D.amber) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
            }
        }
        .padding(2)
        .background(Capsule().fill(p.track))
    }
}

struct TaskRow: View {
    let task: TaskItem
    var onDone: () -> Void = {}
    @EnvironmentObject var store: TaskStore
    @State private var hover = false
    @State private var burst = false

    var body: some View {
        let p = D.p
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { burst = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { store.advance(task); burst = false; onDone() }
            } label: {
                ZStack {
                    Circle().strokeBorder(task.status == .inProgress ? D.amber : p.ink3, lineWidth: 1.5).frame(width: 15, height: 15)
                    if task.status == .inProgress { Circle().trim(from: 0, to: 0.5).fill(D.amber).frame(width: 9, height: 9).rotationEffect(.degrees(90)) }
                    if task.status == .done || burst {
                        Circle().fill(p.ok).frame(width: 15, height: 15)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                    }
                    if burst {
                        ForEach(0..<6, id: \.self) { i in
                            Circle().fill([D.amber, p.ok, D.claude][i % 3]).frame(width: 3, height: 3)
                                .offset(x: cos(Double(i) * .pi / 3) * 13, y: sin(Double(i) * .pi / 3) * 13)
                        }
                    }
                }
                .scaleEffect(burst ? 1.25 : 1)
                .frame(width: 20, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(task.status == .done)
            Text(task.title)
                .font(D.rounded(12, .medium))
                .foregroundStyle(task.status == .done ? p.ink3 : p.ink)
                .strikethrough(task.status == .done || burst, color: p.ink3)
                .lineLimit(1)
            Spacer(minLength: 4)
            if hover {
                HStack(spacing: 2) {
                    if task.status.previous != nil { mini("arrow.uturn.left") { store.retreat(task) } }
                    mini("xmark") { store.delete(task.id) }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? p.track : .clear))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }

    private func mini(_ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: s).font(.system(size: 8.5, weight: .bold)).foregroundStyle(D.p.ink2)
                .frame(width: 18, height: 18).background(Circle().fill(D.p.ink4)).contentShape(Circle())
        }.buttonStyle(PressScale())
    }
}
