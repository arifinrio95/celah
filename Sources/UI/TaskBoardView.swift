import SwiftUI

/// Full Kanban window: projects sidebar + four status columns.
struct TaskBoardView: View {
    @EnvironmentObject var store: TaskStore
    @State private var newProject = ""
    @State private var editingProject: UUID?
    @State private var editName = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 180)
            VLine()
            HStack(spacing: 0) {
                ForEach(TaskStatus.allCases) { s in
                    Column(status: s)
                    if s != .done { VLine() }
                }
            }
        }
        .background(Color.black)
        .frame(minWidth: 900, minHeight: 520)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROJECT").font(Theme.label()).tracking(1.6).foregroundStyle(Theme.ink3)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(store.projects) { p in
                        ProjectRow(project: p, editing: editingProject == p.id, editName: $editName,
                                   onSelect: { store.selectedProjectID = p.id },
                                   onEdit: { editingProject = p.id; editName = p.name },
                                   onCommit: { store.renameProject(p.id, to: editName); editingProject = nil },
                                   onDelete: { store.deleteProject(p.id) })
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ink3)
                TextField("", text: $newProject).overlay(alignment: .leading) { if newProject.isEmpty { Text("New project…").foregroundStyle(Theme.ink3).allowsHitTesting(false) } }
                    .textFieldStyle(.plain).font(Theme.body(12)).foregroundStyle(Theme.ink)
                    .onSubmit { store.addProject(newProject); newProject = "" }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(alignment: .top) { HLine() }
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let editing: Bool
    @Binding var editName: String
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onCommit: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var store: TaskStore
    @State private var hover = false

    var body: some View {
        let on = project.id == store.selectedProjectID
        HStack(spacing: 8) {
            Rectangle().fill(on ? Theme.accent : Color.clear).frame(width: 2, height: 14)
            if editing {
                TextField("", text: $editName).textFieldStyle(.plain).font(Theme.body(12, .medium)).foregroundStyle(Theme.ink)
                    .onSubmit(onCommit)
            } else {
                Text(project.name).font(Theme.body(12, on ? .semibold : .regular)).foregroundStyle(on ? Theme.ink : Theme.ink2).lineLimit(1)
            }
            Spacer(minLength: 4)
            let open = project.tasks.filter { $0.status != .done }.count
            if hover && !editing {
                GlyphButton(symbol: "pencil", size: 9, box: 16, action: onEdit)
                if store.projects.count > 1 { GlyphButton(symbol: "xmark", size: 9, box: 16, action: onDelete) }
            } else if open > 0 {
                Text(verbatim: "\(open)").font(Theme.mono(9.5)).foregroundStyle(Theme.ink3)
            }
        }
        .padding(.leading, 14).padding(.trailing, 12).frame(height: 28)
        .background(on ? Theme.ink4.opacity(0.5) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hover = $0 }
    }
}

private struct Column: View {
    let status: TaskStatus
    @EnvironmentObject var store: TaskStore
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.short).font(Theme.label()).tracking(1.6)
                    .foregroundStyle(status == .inProgress ? Theme.accent : Theme.ink3)
                Text(verbatim: "\(store.count(status))").font(Theme.mono(9.5)).foregroundStyle(Theme.ink3)
                Spacer()
                if status == .done, store.count(.done) > 0 {
                    Button { store.clearDone() } label: {
                        Text("clear").font(Theme.mono(9)).foregroundStyle(Theme.ink3)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(store.tasks(status)) { t in KanbanCard(task: t) }
                }
                .padding(.horizontal, 12)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ink3)
                TextField("", text: $newTitle).overlay(alignment: .leading) { if newTitle.isEmpty { Text("Add…").foregroundStyle(Theme.ink3).allowsHitTesting(false) } }
                    .textFieldStyle(.plain).font(Theme.body(12)).foregroundStyle(Theme.ink)
                    .onSubmit { store.addTask(newTitle, status: status); newTitle = "" }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(alignment: .top) { HLine() }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct KanbanCard: View {
    let task: TaskItem
    @EnvironmentObject var store: TaskStore
    @State private var hover = false
    @State private var editing = false
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editing {
                TextField("", text: $text).textFieldStyle(.plain).font(Theme.body(12)).foregroundStyle(Theme.ink)
                    .onSubmit { store.rename(task.id, to: text); editing = false }
            } else {
                Text(task.title).font(Theme.body(12)).foregroundStyle(task.status == .done ? Theme.ink3 : Theme.ink)
                    .strikethrough(task.status == .done, color: Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(count: 2) { text = task.title; editing = true }
            }
            HStack(spacing: 4) {
                Text(Fmt.dayShort(task.status == .done ? task.updatedAt : task.createdAt)).font(Theme.mono(9)).foregroundStyle(Theme.ink3)
                Spacer()
                if hover {
                    if task.status.previous != nil { GlyphButton(symbol: "arrow.left", size: 9, box: 18) { store.retreat(task) } }
                    if task.status.next != nil { GlyphButton(symbol: "arrow.right", size: 9, box: 18) { store.advance(task) } }
                    GlyphButton(symbol: "xmark", size: 9, box: 18) { store.delete(task.id) }
                }
            }
            .frame(height: 18)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.ink4.opacity(hover ? 0.6 : 0.35)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1))
        .onHover { hover = $0 }
    }
}
