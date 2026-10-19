import Foundation
import Combine

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case backlog, todo, inProgress, done
    var id: String { rawValue }
    var label: String {
        switch self {
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
    var short: String {
        switch self {
        case .backlog: return "BACKLOG"
        case .todo: return "TO DO"
        case .inProgress: return "PROGRESS"
        case .done: return "DONE"
        }
    }
    var symbol: String {
        switch self {
        case .backlog: return "circle.dotted"
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }
    var next: TaskStatus? { TaskStatus.allCases.firstIndex(of: self).flatMap { TaskStatus.allCases.indices.contains($0 + 1) ? TaskStatus.allCases[$0 + 1] : nil } }
    var previous: TaskStatus? { TaskStatus.allCases.firstIndex(of: self).flatMap { $0 > 0 ? TaskStatus.allCases[$0 - 1] : nil } }
}

struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var status: TaskStatus
    var createdAt = Date()
    var updatedAt = Date()
}

struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var tasks: [TaskItem] = []
}

/// Projects → tasks, persisted as JSON in ~/Library/Application Support/Celah/tasks.json.
final class TaskStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published var selectedProjectID: UUID? {
        didSet { UserDefaults.standard.set(selectedProjectID?.uuidString, forKey: "tasks.project") }
    }
    @Published var selectedStatus: TaskStatus = .todo

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Celah")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tasks.json")
    }()
    private var saveWork: DispatchWorkItem?

    init() {
        if let data = try? Data(contentsOf: url), let p = try? JSONDecoder().decode([Project].self, from: data) {
            projects = p
        }
        if projects.isEmpty { projects = [Project(name: "General")] }
        if let s = UserDefaults.standard.string(forKey: "tasks.project"), let id = UUID(uuidString: s), projects.contains(where: { $0.id == id }) {
            selectedProjectID = id
        } else {
            selectedProjectID = projects.first?.id
        }
    }

    var selected: Project? { projects.first { $0.id == selectedProjectID } ?? projects.first }
    var selectedIndex: Int? { projects.firstIndex { $0.id == selectedProjectID } ?? (projects.isEmpty ? nil : 0) }

    func tasks(_ status: TaskStatus, in project: Project? = nil) -> [TaskItem] {
        ((project ?? selected)?.tasks ?? []).filter { $0.status == status }
            .sorted { $0.status == .done ? $0.updatedAt > $1.updatedAt : $0.createdAt < $1.createdAt }
    }
    func count(_ status: TaskStatus, in project: Project? = nil) -> Int {
        ((project ?? selected)?.tasks ?? []).filter { $0.status == status }.count
    }
    var activeCount: Int { (selected?.tasks ?? []).filter { $0.status == .todo || $0.status == .inProgress }.count }

    // MARK: - Projects

    @discardableResult
    func addProject(_ name: String) -> Project {
        let p = Project(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Project" : name.trimmingCharacters(in: .whitespaces))
        projects.append(p)
        selectedProjectID = p.id
        save()
        return p
    }

    func renameProject(_ id: UUID, to name: String) {
        guard let i = projects.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        projects[i].name = name.trimmingCharacters(in: .whitespaces)
        save()
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        if projects.isEmpty { projects = [Project(name: "General")] }
        if selectedProjectID == id || selectedProjectID == nil { selectedProjectID = projects.first?.id }
        save()
    }

    func selectProject(offset: Int) {
        guard let i = selectedIndex, !projects.isEmpty else { return }
        selectedProjectID = projects[(i + offset + projects.count) % projects.count].id
    }

    // MARK: - Tasks

    func addTask(_ title: String, status: TaskStatus, projectID: UUID? = nil) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = projects.firstIndex(where: { $0.id == (projectID ?? selectedProjectID) }) ?? (projects.isEmpty ? nil : 0) else { return }
        projects[i].tasks.append(TaskItem(title: t, status: status))
        save()
    }

    func move(_ taskID: UUID, to status: TaskStatus) {
        for i in projects.indices {
            if let j = projects[i].tasks.firstIndex(where: { $0.id == taskID }) {
                projects[i].tasks[j].status = status
                projects[i].tasks[j].updatedAt = Date()
                save()
                return
            }
        }
    }

    func advance(_ task: TaskItem) { if let n = task.status.next { move(task.id, to: n) } }
    func retreat(_ task: TaskItem) { if let p = task.status.previous { move(task.id, to: p) } }

    func rename(_ taskID: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        for i in projects.indices {
            if let j = projects[i].tasks.firstIndex(where: { $0.id == taskID }) {
                projects[i].tasks[j].title = t
                save()
                return
            }
        }
    }

    func delete(_ taskID: UUID) {
        for i in projects.indices { projects[i].tasks.removeAll { $0.id == taskID } }
        save()
    }

    func clearDone(projectID: UUID? = nil) {
        guard let i = projects.firstIndex(where: { $0.id == (projectID ?? selectedProjectID) }) else { return }
        projects[i].tasks.removeAll { $0.status == .done }
        save()
    }

    private func save() {
        saveWork?.cancel()
        let snapshot = projects
        let w = DispatchWorkItem { [url] in
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
        saveWork = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: w)
    }
}
