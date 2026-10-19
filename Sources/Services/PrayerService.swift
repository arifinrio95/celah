import Foundation
import AppKit
import CoreLocation
import Combine

final class PrayerService: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct PrayerTime: Identifiable {
        let key: String
        let name: String
        let short: String
        let date: Date
        var isTomorrow = false
        var id: String { key + (isTomorrow ? "+1" : "") }
    }

    @Published private(set) var today: [PrayerTime] = []
    @Published private(set) var tomorrowFirst: PrayerTime?
    @Published private(set) var sunrise: Date?
    @Published private(set) var locationName = ""
    @Published private(set) var timeZone = TimeZone.current

    weak var notifier: Notifier?

    private let settings: AppSettings
    private var computedDay: Date?
    private var gpsCoord: CLLocationCoordinate2D?
    private var gpsName: String?
    private lazy var locationManager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        return m
    }()

    private static let names: [(String, String, String)] = [
        ("fajr", "Fajr", "Fajr"), ("dhuhr", "Dhuhr", "Dhuhr"), ("asr", "Asr", "Asr"),
        ("maghrib", "Maghrib", "Maghrib"), ("isha", "Isha", "Isha"),
    ]

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    func start() {
        recompute()
        if settings.useGPS { locationModeChanged() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.recompute()
        }
    }

    func locationModeChanged() {
        if settings.useGPS {
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        } else {
            locationManager.stopUpdatingLocation()
            gpsCoord = nil
            gpsName = nil
            recompute()
        }
    }

    /// Called every clock tick: recompute when the day flips.
    func tick(_ now: Date) {
        if let d = computedDay, !Calendar.current.isDate(d, inSameDayAs: now) { recompute() }
    }

    func recompute() {
        let city = settings.city
        let lat: Double, lng: Double
        let tz: TimeZone
        if settings.useGPS, let c = gpsCoord {
            lat = c.latitude; lng = c.longitude; tz = .current
            locationName = gpsName ?? String(format: "%.2f, %.2f", lat, lng)
        } else {
            lat = city.lat; lng = city.lng; tz = city.timeZone
            locationName = city.name
        }
        timeZone = tz
        var calc = PrayerCalculator(lat: lat, lng: lng)
        calc.params.ihtiyatMinutes = Double(settings.ihtiyat)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now = Date()
        let todayTimes = Self.build(calc, day: now, cal: cal, tz: tz)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let tomorrowTimes = Self.build(calc, day: tomorrow, cal: cal, tz: tz)

        today = todayTimes.list
        sunrise = todayTimes.sunrise
        tomorrowFirst = tomorrowTimes.list.first.map { var p = $0; p.isTomorrow = true; return p }
        computedDay = now
        scheduleNotifications()
    }

    private static func build(_ calc: PrayerCalculator, day: Date, cal: Calendar, tz: TimeZone) -> (list: [PrayerTime], sunrise: Date) {
        let comps = cal.dateComponents([.year, .month, .day], from: day)
        let start = cal.startOfDay(for: day)
        let offset = Double(tz.secondsFromGMT(for: start)) / 3600
        let t = calc.times(year: comps.year!, month: comps.month!, day: comps.day!, tzOffsetHours: offset)
        func date(_ h: Double) -> Date { start.addingTimeInterval(h * 3600) }
        let values: [String: Double] = ["fajr": t.fajr, "dhuhr": t.dhuhr, "asr": t.asr, "maghrib": t.maghrib, "isha": t.isha]
        let list = names.map { PrayerTime(key: $0.0, name: $0.1, short: $0.2, date: date(values[$0.0]!)) }
        return (list, date(t.sunrise))
    }

    func next(at now: Date) -> PrayerTime? {
        today.first { $0.date > now } ?? tomorrowFirst
    }

    func current(at now: Date) -> PrayerTime? {
        today.last { $0.date <= now }
    }

    // MARK: - Notifications

    private func scheduleNotifications() {
        guard let notifier else { return }
        notifier.clearPrayerReminders()
        guard settings.prayerNotify else { return }
        let now = Date()
        for p in today where p.date > now {
            let hm = Fmt.hm(p.date, tz: timeZone)
            notifier.schedule(id: "prayer.\(p.key)", at: p.date,
                              title: "\(p.name) time", body: "It's \(p.name) time · \(hm) · \(locationName)")
            let pre = p.date.addingTimeInterval(-Double(settings.preMinutes) * 60)
            if settings.preMinutes > 0, pre > now {
                notifier.schedule(id: "prayer.pre.\(p.key)", at: pre,
                                  title: "\(p.name) in \(settings.preMinutes) min", body: "\(p.name) at \(hm)")
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        manager.stopUpdatingLocation()
        gpsCoord = loc.coordinate
        recompute()
        CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "en_US")) { [weak self] marks, _ in
            guard let self, let m = marks?.first else { return }
            self.gpsName = m.locality ?? m.subAdministrativeArea ?? m.administrativeArea
            DispatchQueue.main.async { self.recompute() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if gpsCoord == nil { DispatchQueue.main.async { self.recompute() } }
    }
}
