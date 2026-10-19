import Foundation
import Combine

/// Bundled mushaf (Uthmani text + Kemenag-style Indonesian translation), one ayah at a time.
/// Reading position is saved automatically.
final class QuranStore: ObservableObject {
    struct Surah {
        let n: Int
        let ar: String
        let latin: String
        let en: String
        let count: Int
        let type: String
    }

    struct Ayah {
        let surah: Int
        let number: Int
        let arabic: String
        let translation: String
    }

    @Published private(set) var loaded = false
    @Published var index: Int {
        didSet {
            let d = UserDefaults.standard
            d.set(index, forKey: "quran.index")
            d.set(Date(), forKey: "quran.lastReadAt")
        }
    }

    private(set) var surahs: [Surah] = []
    private(set) var ayahs: [Ayah] = []
    /// Index of the first ayah of each surah (0-based surah order).
    private(set) var surahStart: [Int] = []

    init() {
        index = UserDefaults.standard.integer(forKey: "quran.index")
    }

    var count: Int { ayahs.count }
    var current: Ayah? { loaded && ayahs.indices.contains(index) ? ayahs[index] : nil }
    var currentSurah: Surah? { current.flatMap { a in surahs.indices.contains(a.surah - 1) ? surahs[a.surah - 1] : nil } }
    var lastReadAt: Date? { UserDefaults.standard.object(forKey: "quran.lastReadAt") as? Date }

    func load() {
        guard !loaded else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let url = Bundle.main.url(forResource: "quran", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let s = json["surahs"] as? [[String: Any]],
                  let a = json["ayahs"] as? [[Any]] else { return }
            let surahs = s.map {
                Surah(n: $0["n"] as? Int ?? 0, ar: $0["ar"] as? String ?? "", latin: $0["latin"] as? String ?? "",
                      en: $0["en"] as? String ?? "", count: $0["count"] as? Int ?? 0, type: $0["type"] as? String ?? "")
            }
            let ayahs = a.compactMap { row -> Ayah? in
                guard row.count == 4, let s = row[0] as? Int, let n = row[1] as? Int,
                      let ar = row[2] as? String, let id = row[3] as? String else { return nil }
                return Ayah(surah: s, number: n, arabic: ar, translation: id)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.surahs = surahs
                self.ayahs = ayahs
                var starts: [Int] = []
                for (i, a) in ayahs.enumerated() where a.number == 1 { starts.append(i) }
                self.surahStart = starts
                if !ayahs.indices.contains(self.index) { self.index = 0 }
                self.loaded = true
            }
        }
    }

    func next() {
        guard loaded else { return }
        index = index + 1 < ayahs.count ? index + 1 : 0
    }

    /// Ayah indices of a surah (1-based surah number).
    func range(ofSurah n: Int) -> Range<Int> {
        guard surahStart.indices.contains(n - 1) else { return 0..<0 }
        let start = surahStart[n - 1]
        let end = surahStart.indices.contains(n) ? surahStart[n] : ayahs.count
        return start..<end
    }

    func jump(toSurah n: Int) {
        let r = range(ofSurah: n)
        if !r.isEmpty { index = r.lowerBound }
    }

    func prev() {
        guard loaded else { return }
        index = index > 0 ? index - 1 : ayahs.count - 1
    }
}
