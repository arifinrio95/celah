import Foundation

struct City: Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double
    let tz: String

    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }
}

enum Cities {
    static let all: [City] = [
        City(id: "tangsel", name: "Tangerang Selatan", lat: -6.2886, lng: 106.7179, tz: "Asia/Jakarta"),
        City(id: "jakarta", name: "Jakarta", lat: -6.2088, lng: 106.8456, tz: "Asia/Jakarta"),
        City(id: "tangerang", name: "Tangerang", lat: -6.1783, lng: 106.6319, tz: "Asia/Jakarta"),
        City(id: "bekasi", name: "Bekasi", lat: -6.2383, lng: 106.9756, tz: "Asia/Jakarta"),
        City(id: "depok", name: "Depok", lat: -6.4025, lng: 106.7942, tz: "Asia/Jakarta"),
        City(id: "bogor", name: "Bogor", lat: -6.5971, lng: 106.8060, tz: "Asia/Jakarta"),
        City(id: "bandung", name: "Bandung", lat: -6.9175, lng: 107.6191, tz: "Asia/Jakarta"),
        City(id: "semarang", name: "Semarang", lat: -6.9667, lng: 110.4167, tz: "Asia/Jakarta"),
        City(id: "yogyakarta", name: "Yogyakarta", lat: -7.7956, lng: 110.3695, tz: "Asia/Jakarta"),
        City(id: "surabaya", name: "Surabaya", lat: -7.2575, lng: 112.7521, tz: "Asia/Jakarta"),
        City(id: "malang", name: "Malang", lat: -7.9666, lng: 112.6326, tz: "Asia/Jakarta"),
        City(id: "medan", name: "Medan", lat: 3.5952, lng: 98.6722, tz: "Asia/Jakarta"),
        City(id: "palembang", name: "Palembang", lat: -2.9761, lng: 104.7754, tz: "Asia/Jakarta"),
        City(id: "pekanbaru", name: "Pekanbaru", lat: 0.5071, lng: 101.4478, tz: "Asia/Jakarta"),
        City(id: "padang", name: "Padang", lat: -0.9471, lng: 100.4172, tz: "Asia/Jakarta"),
        City(id: "bandaaceh", name: "Banda Aceh", lat: 5.5483, lng: 95.3238, tz: "Asia/Jakarta"),
        City(id: "batam", name: "Batam", lat: 1.0456, lng: 104.0305, tz: "Asia/Jakarta"),
        City(id: "lampung", name: "Bandar Lampung", lat: -5.3971, lng: 105.2668, tz: "Asia/Jakarta"),
        City(id: "pontianak", name: "Pontianak", lat: -0.0263, lng: 109.3425, tz: "Asia/Jakarta"),
        City(id: "denpasar", name: "Denpasar", lat: -8.6705, lng: 115.2126, tz: "Asia/Makassar"),
        City(id: "mataram", name: "Mataram", lat: -8.5833, lng: 116.1167, tz: "Asia/Makassar"),
        City(id: "makassar", name: "Makassar", lat: -5.1477, lng: 119.4327, tz: "Asia/Makassar"),
        City(id: "balikpapan", name: "Balikpapan", lat: -1.2379, lng: 116.8529, tz: "Asia/Makassar"),
        City(id: "banjarmasin", name: "Banjarmasin", lat: -3.3194, lng: 114.5908, tz: "Asia/Makassar"),
        City(id: "manado", name: "Manado", lat: 1.4748, lng: 124.8421, tz: "Asia/Makassar"),
        City(id: "ambon", name: "Ambon", lat: -3.6954, lng: 128.1814, tz: "Asia/Jayapura"),
        City(id: "jayapura", name: "Jayapura", lat: -2.5337, lng: 140.7181, tz: "Asia/Jayapura"),
    ]
}
