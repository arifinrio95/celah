import Foundation
import Combine

final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var cityID: String { didSet { d.set(cityID, forKey: "cityID") } }
    @Published var useGPS: Bool { didSet { d.set(useGPS, forKey: "useGPS") } }
    @Published var ihtiyat: Int { didSet { d.set(ihtiyat, forKey: "ihtiyat") } }
    @Published var prayerNotify: Bool { didSet { d.set(prayerNotify, forKey: "prayerNotify") } }
    @Published var preMinutes: Int { didSet { d.set(preMinutes, forKey: "preMinutes") } }
    @Published var wings: Bool { didSet { d.set(wings, forKey: "wings") } }
    @Published var calendarIDs: [String] { didSet { d.set(calendarIDs, forKey: "calendarIDs") } }
    @Published var modules: [BoardModule] { didSet { d.set(modules.map(\.rawValue), forKey: "board.modules") } }
    /// Board look: "porcelain" (paper under the black lip) or "ink" (smoked glass).
    @Published var look: String { didSet { d.set(look, forKey: "board.look") } }

    init() {
        cityID = d.string(forKey: "cityID") ?? "tangsel"
        useGPS = d.bool(forKey: "useGPS")
        ihtiyat = d.object(forKey: "ihtiyat") == nil ? 2 : d.integer(forKey: "ihtiyat")
        prayerNotify = d.object(forKey: "prayerNotify") == nil ? true : d.bool(forKey: "prayerNotify")
        preMinutes = d.object(forKey: "preMinutes") == nil ? 10 : d.integer(forKey: "preMinutes")
        wings = d.object(forKey: "wings") == nil ? true : d.bool(forKey: "wings")
        calendarIDs = d.stringArray(forKey: "calendarIDs") ?? []
        look = d.string(forKey: "board.look") ?? "porcelain"
        if let raw = d.stringArray(forKey: "board.modules") {
            modules = raw.compactMap(BoardModule.init(rawValue:))
        } else {
            modules = BoardModule.defaultOrder
        }
    }


    func isOn(_ m: BoardModule) -> Bool { modules.contains(m) }

    func setOn(_ m: BoardModule, _ on: Bool) {
        if on {
            if !modules.contains(m), modules.count < BoardLayout.maxModules { modules.append(m) }
        } else {
            modules.removeAll { $0 == m }
        }
    }

    func move(_ m: BoardModule, by delta: Int) {
        guard let i = modules.firstIndex(of: m) else { return }
        let j = i + delta
        guard modules.indices.contains(j) else { return }
        modules.swapAt(i, j)
    }

    func resetModules() { modules = BoardModule.defaultOrder }

    var city: City { Cities.all.first { $0.id == cityID } ?? Cities.all[0] }
}
