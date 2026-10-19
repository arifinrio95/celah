import Foundation
import Darwin

final class SystemStats: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memUsed: UInt64 = 0
    @Published private(set) var diskUsed: UInt64 = 0
    @Published private(set) var diskFree: UInt64 = 0
    @Published private(set) var diskTotal: UInt64 = 0
    let memTotal = ProcessInfo.processInfo.physicalMemory
    let chip: String = SystemStats.readChip()

    private var prev: (busy: UInt64, total: UInt64)?
    private var prevAt = Date.distantPast
    private var cpuSmoothed: Double?
    private var timer: Timer?
    private var diskSampledAt = Date.distantPast
    private let q = DispatchQueue(label: "id.datasans.celah.stats", qos: .utility)

    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.sample() }
        timer?.tolerance = 1
    }

    func stop() { timer?.invalidate(); timer = nil }

    func sample() {
        q.async { [weak self] in
            guard let self else { return }
            // Only compute CPU over windows of at least 1.5 s; shorter windows are noisy.
            let cpu: Double? = Date().timeIntervalSince(self.prevAt) >= 1.5 ? self.sampleCPU() : nil
            let mem = Self.readMemoryUsed()
            var disk: (used: UInt64, free: UInt64, total: UInt64)? = nil
            if Date().timeIntervalSince(self.diskSampledAt) > 60 {
                disk = Self.readDisk()
                self.diskSampledAt = Date()
            }
            DispatchQueue.main.async {
                if let cpu { self.cpu = cpu }
                self.memUsed = mem
                if let disk { self.diskUsed = disk.used; self.diskFree = disk.free; self.diskTotal = disk.total }
            }
        }
    }

    private func sampleCPU() -> Double? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t? = nil
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(cpuCount) {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let sys = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            busy += user + sys + nice
            total += user + sys + nice + idle
        }
        defer { prev = (busy, total); prevAt = Date() }
        guard let prev, total > prev.total else { return nil }
        let raw = Double(busy - prev.busy) / Double(total - prev.total)
        // Exponential smoothing so the bar glides instead of jittering.
        let smoothed = cpuSmoothed.map { $0 * 0.6 + raw * 0.4 } ?? raw
        cpuSmoothed = smoothed
        return smoothed
    }

    private static func readMemoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        // Activity Monitor's "Memory Used": app memory (internal − purgeable) + wired + compressed.
        let app = UInt64(max(0, Int64(stats.internal_page_count) - Int64(stats.purgeable_count)))
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private static func readDisk() -> (used: UInt64, free: UInt64, total: UInt64)? {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        let t = UInt64(total), f = UInt64(max(0, free))
        return (t - min(t, f), f, t)
    }

    private static func readChip() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let name = String(cString: buf)
        let gb = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        return "\(name) · \(gb) GB"
    }
}
