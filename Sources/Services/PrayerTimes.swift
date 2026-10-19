import Foundation

/// Astronomical prayer-time calculation (PrayTimes.org method), Kemenag RI parameters by default.
struct PrayerCalculator {
    struct Params {
        var fajrAngle = 20.0
        var ishaAngle = 18.0
        var asrFactor = 1.0      // Shafi'i
        var maghribMinutes = 0.0 // after sunset
        var dhuhrMinutes = 0.0
        var imsakMinutes = 10.0
        var ihtiyatMinutes = 2.0 // Kemenag safety margin
    }

    struct Times {
        var imsak = 0.0, fajr = 0.0, sunrise = 0.0, dhuhr = 0.0, asr = 0.0, sunset = 0.0, maghrib = 0.0, isha = 0.0
    }

    let lat: Double
    let lng: Double
    var params = Params()

    /// Returns prayer times as fractional hours (local time of `tzOffsetHours`) for the given civil date.
    func times(year: Int, month: Int, day: Int, tzOffsetHours: Double) -> Times {
        let jd = julian(year: year, month: month, day: day) - lng / (15 * 24)
        var t = Times(imsak: 5, fajr: 5, sunrise: 6, dhuhr: 12, asr: 13, sunset: 18, maghrib: 18, isha: 18)
        for _ in 0..<2 { t = compute(t, jd: jd) }
        let offset = tzOffsetHours - lng / 15
        t.fajr += offset; t.sunrise += offset; t.dhuhr += offset; t.asr += offset
        t.sunset += offset; t.maghrib += offset; t.isha += offset
        t.dhuhr += params.dhuhrMinutes / 60
        t.maghrib = t.sunset + params.maghribMinutes / 60
        let ih = params.ihtiyatMinutes / 60
        t.fajr += ih; t.dhuhr += ih; t.asr += ih; t.maghrib += ih; t.isha += ih
        t.sunrise -= ih
        t.imsak = t.fajr - params.imsakMinutes / 60
        return t
    }

    private func compute(_ t: Times, jd: Double) -> Times {
        var r = t
        r.fajr = sunAngleTime(jd, angle: params.fajrAngle, time: t.fajr / 24, ccw: true)
        r.sunrise = sunAngleTime(jd, angle: riseSetAngle, time: t.sunrise / 24, ccw: true)
        r.dhuhr = midDay(jd, time: t.dhuhr / 24)
        r.asr = asrTime(jd, factor: params.asrFactor, time: t.asr / 24)
        r.sunset = sunAngleTime(jd, angle: riseSetAngle, time: t.sunset / 24, ccw: false)
        r.maghrib = r.sunset
        r.isha = sunAngleTime(jd, angle: params.ishaAngle, time: t.isha / 24, ccw: false)
        return r
    }

    private var riseSetAngle: Double { 0.833 }

    private func sunPosition(_ jd: Double) -> (decl: Double, eqt: Double) {
        let d = jd - 2451545.0
        let g = fixAngle(357.529 + 0.98560028 * d)
        let q = fixAngle(280.459 + 0.98564736 * d)
        let l = fixAngle(q + 1.915 * dsin(g) + 0.020 * dsin(2 * g))
        let e = 23.439 - 0.00000036 * d
        let ra = datan2(dcos(e) * dsin(l), dcos(l)) / 15
        let eqt = q / 15 - fixHour(ra)
        let decl = darcsin(dsin(e) * dsin(l))
        return (decl, eqt)
    }

    private func midDay(_ jd: Double, time: Double) -> Double {
        fixHour(12 - sunPosition(jd + time).eqt)
    }

    private func sunAngleTime(_ jd: Double, angle: Double, time: Double, ccw: Bool) -> Double {
        let decl = sunPosition(jd + time).decl
        let noon = midDay(jd, time: time)
        let cosT = (-dsin(angle) - dsin(decl) * dsin(lat)) / (dcos(decl) * dcos(lat))
        let t = darccos(max(-1, min(1, cosT))) / 15
        return noon + (ccw ? -t : t)
    }

    private func asrTime(_ jd: Double, factor: Double, time: Double) -> Double {
        let decl = sunPosition(jd + time).decl
        let angle = -darccot(factor + dtan(abs(lat - decl)))
        return sunAngleTime(jd, angle: angle, time: time, ccw: false)
    }

    private func julian(year: Int, month: Int, day: Int) -> Double {
        var y = Double(year), m = Double(month)
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(y / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + Double(day) + b - 1524.5
    }

    // Degree-based trig helpers
    private func dsin(_ d: Double) -> Double { sin(d * .pi / 180) }
    private func dcos(_ d: Double) -> Double { cos(d * .pi / 180) }
    private func dtan(_ d: Double) -> Double { tan(d * .pi / 180) }
    private func darcsin(_ x: Double) -> Double { asin(x) * 180 / .pi }
    private func darccos(_ x: Double) -> Double { acos(x) * 180 / .pi }
    private func darccot(_ x: Double) -> Double { atan(1 / x) * 180 / .pi }
    private func datan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }
    private func fixAngle(_ a: Double) -> Double { a - 360 * floor(a / 360) }
    private func fixHour(_ h: Double) -> Double { h - 24 * floor(h / 24) }
}
