import Foundation

/// Every instrument that can sit on the board. Order and visibility live in AppSettings.
enum BoardModule: String, CaseIterable, Identifiable, Codable {
    case music, usage, prayer, tasks, system, quran

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return "Music"
        case .usage: return "AI Usage"
        case .prayer: return "Prayer"
        case .tasks: return "Tasks"
        case .system: return "System"
        case .quran: return "Qur'an"
        }
    }

    static let defaultOrder: [BoardModule] = [.music, .usage, .prayer, .tasks, .system, .quran]
}

enum BoardLayout {
    static let maxModules = 6

    /// Cells per row for a module count. Rows are split evenly, so the grid stays balanced:
    /// 1 full, 2 side by side, 3 across, 4 as 2×2, 5 as 3 over 2, 6 as 3×2.
    static func rows(for n: Int) -> [Int] {
        switch min(n, maxModules) {
        case 0: return []
        case 1: return [1]
        case 2: return [2]
        case 3: return [3]
        case 4: return [2, 2]
        case 5: return [3, 2]
        default: return [3, 3]
        }
    }
}
