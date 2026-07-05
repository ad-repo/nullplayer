import AppKit
import Darwin
import Foundation

extension Notification.Name {
    static let networkThroughputDataUpdated = Notification.Name("networkThroughputDataUpdated")
}

struct NetworkThroughputPoint: Equatable {
    let downBytesPerSecond: Double
    let upBytesPerSecond: Double
}

struct NetworkThroughputSnapshot: Equatable {
    let interface: NetworkInterfaceResolver.InterfaceInfo?
    let downBytesPerSecond: Double
    let upBytesPerSecond: Double
    let sessionPeakDownBytesPerSecond: Double
    let sessionPeakUpBytesPerSecond: Double
    let dailyDownBytes: UInt64
    let dailyUpBytes: UInt64
    let history: [NetworkThroughputPoint]
    let updatedAt: Date
}

struct NetworkByteCounters: Equatable {
    let interfaceName: String
    let inputBytes: UInt64
    let outputBytes: UInt64
}

enum NetworkThroughputResetReason: Equatable {
    case none
    case firstSample
    case interfaceChanged
    case dayRollover
    case counterDecrease
    case gapExceeded
}

struct NetworkThroughputTickResult: Equatable {
    let downBytesPerSecond: Double
    let upBytesPerSecond: Double
    let dailyDownBytes: UInt64
    let dailyUpBytes: UInt64
    let currentDay: String
    let resetReason: NetworkThroughputResetReason

    var didAccumulate: Bool { resetReason == .none }
}

enum NetworkThroughputFormatting {
    static func bytesPerSecond(_ value: Double) -> String {
        format(value, suffix: "/s")
    }

    static func bytes(_ value: UInt64) -> String {
        format(Double(value), suffix: "")
    }

    private static func format(_ value: Double, suffix: String) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var scaled = max(0, value)
        var unitIndex = 0
        while scaled >= 1024, unitIndex < units.count - 1 {
            scaled /= 1024
            unitIndex += 1
        }

        let number: String
        if unitIndex == 0 {
            number = String(format: "%.0f", scaled)
        } else if scaled < 10 {
            number = String(format: "%.1f", scaled)
        } else {
            number = String(format: "%.0f", scaled)
        }
        return "\(number) \(units[unitIndex])\(suffix)"
    }
}

final class NetworkThroughputMonitor {
    static let selectedInterfaceDefaultsKey = "NetworkMonitorSelectedInterfaceName"

    private enum DefaultsKey {
        static let day = "NetworkMonitorDailyTotalsDay"
        static let down = "NetworkMonitorDailyDownBytes"
        static let up = "NetworkMonitorDailyUpBytes"
    }

    let sampleInterval: TimeInterval
    var onUpdate: ((NetworkThroughputSnapshot) -> Void)?

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let historyLimit: Int
    private var timer: Timer?
    private var selectedInterfaceName: String?
    private var previousCounters: NetworkByteCounters?
    private var previousSampleAt: Date?
    private var sessionPeakDown: Double = 0
    private var sessionPeakUp: Double = 0
    private var dailyDown: UInt64 = 0
    private var dailyUp: UInt64 = 0
    private var currentDay: String
    private var history: [NetworkThroughputPoint] = []
    private var interfaces: [NetworkInterfaceResolver.InterfaceInfo] = []

    init(
        sampleInterval: TimeInterval = 0.5,
        historyLimit: Int = 90,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.sampleInterval = sampleInterval
        self.historyLimit = historyLimit
        self.defaults = defaults
        self.calendar = calendar
        self.currentDay = Self.dayString(for: Date(), calendar: calendar)
        loadPreferences()
    }

    deinit {
        stop()
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        refreshInterfaces()
        loadPreferences()
        reselectInterfaceIfNeeded()
        seedBaselineAndPublish()

        timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousCounters = nil
        previousSampleAt = nil
    }

    func availableInterfaces() -> [NetworkInterfaceResolver.InterfaceInfo] {
        refreshInterfaces()
        return interfaces
    }

    func selectedInterface() -> NetworkInterfaceResolver.InterfaceInfo? {
        refreshInterfaces()
        return interface(named: selectedInterfaceName)
    }

    func cycleInterface() {
        refreshInterfaces()
        guard !interfaces.isEmpty else { return }
        let currentIndex = interfaces.firstIndex { $0.name == selectedInterfaceName } ?? -1
        let nextIndex = (currentIndex + 1) % interfaces.count
        setSelectedInterface(interfaces[nextIndex].name)
    }

    func setSelectedInterface(_ name: String) {
        selectedInterfaceName = name
        defaults.set(name, forKey: Self.selectedInterfaceDefaultsKey)
        previousCounters = nil
        previousSampleAt = nil
        history.removeAll(keepingCapacity: true)
        seedBaselineAndPublish()
    }

    func tick(now: Date = Date()) {
        refreshInterfaces()
        reselectInterfaceIfNeeded()
        rollDayIfNeeded(now)

        guard let selectedInterfaceName,
              let currentCounters = Self.readCountersByInterface()[selectedInterfaceName] else {
            publish(down: 0, up: 0, now: now)
            previousCounters = nil
            previousSampleAt = nil
            return
        }

        defer {
            previousCounters = currentCounters
            previousSampleAt = now
        }

        let result = Self.evaluateTick(
            previousCounters: previousCounters,
            previousSampleAt: previousSampleAt,
            currentCounters: currentCounters,
            now: now,
            currentDay: currentDay,
            dailyDownBytes: dailyDown,
            dailyUpBytes: dailyUp,
            sampleInterval: sampleInterval,
            calendar: calendar
        )
        currentDay = result.currentDay
        dailyDown = result.dailyDownBytes
        dailyUp = result.dailyUpBytes
        if result.resetReason == .dayRollover || result.didAccumulate {
            persistDailyTotals()
        }

        publish(down: result.downBytesPerSecond, up: result.upBytesPerSecond, now: now)
    }

    static func allowedSamplingGap(sampleInterval: TimeInterval) -> TimeInterval {
        max(2.0, min(5.0, sampleInterval * 3.0))
    }

    static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    static func evaluateTick(
        previousCounters: NetworkByteCounters?,
        previousSampleAt: Date?,
        currentCounters: NetworkByteCounters,
        now: Date,
        currentDay: String,
        dailyDownBytes: UInt64,
        dailyUpBytes: UInt64,
        sampleInterval: TimeInterval,
        calendar: Calendar = .current
    ) -> NetworkThroughputTickResult {
        let day = dayString(for: now, calendar: calendar)
        if day != currentDay {
            return NetworkThroughputTickResult(
                downBytesPerSecond: 0,
                upBytesPerSecond: 0,
                dailyDownBytes: 0,
                dailyUpBytes: 0,
                currentDay: day,
                resetReason: .dayRollover
            )
        }

        guard let previousCounters, let previousSampleAt else {
            return NetworkThroughputTickResult(
                downBytesPerSecond: 0,
                upBytesPerSecond: 0,
                dailyDownBytes: dailyDownBytes,
                dailyUpBytes: dailyUpBytes,
                currentDay: currentDay,
                resetReason: .firstSample
            )
        }

        guard previousCounters.interfaceName == currentCounters.interfaceName else {
            return NetworkThroughputTickResult(
                downBytesPerSecond: 0,
                upBytesPerSecond: 0,
                dailyDownBytes: dailyDownBytes,
                dailyUpBytes: dailyUpBytes,
                currentDay: currentDay,
                resetReason: .interfaceChanged
            )
        }

        let elapsed = now.timeIntervalSince(previousSampleAt)
        guard elapsed > 0, elapsed <= allowedSamplingGap(sampleInterval: sampleInterval) else {
            return NetworkThroughputTickResult(
                downBytesPerSecond: 0,
                upBytesPerSecond: 0,
                dailyDownBytes: dailyDownBytes,
                dailyUpBytes: dailyUpBytes,
                currentDay: currentDay,
                resetReason: .gapExceeded
            )
        }

        guard currentCounters.inputBytes >= previousCounters.inputBytes,
              currentCounters.outputBytes >= previousCounters.outputBytes else {
            return NetworkThroughputTickResult(
                downBytesPerSecond: 0,
                upBytesPerSecond: 0,
                dailyDownBytes: dailyDownBytes,
                dailyUpBytes: dailyUpBytes,
                currentDay: currentDay,
                resetReason: .counterDecrease
            )
        }

        let downDelta = currentCounters.inputBytes - previousCounters.inputBytes
        let upDelta = currentCounters.outputBytes - previousCounters.outputBytes
        let downSum = dailyDownBytes.addingReportingOverflow(downDelta)
        let upSum = dailyUpBytes.addingReportingOverflow(upDelta)
        return NetworkThroughputTickResult(
            downBytesPerSecond: Double(downDelta) / elapsed,
            upBytesPerSecond: Double(upDelta) / elapsed,
            dailyDownBytes: downSum.overflow ? UInt64.max : downSum.partialValue,
            dailyUpBytes: upSum.overflow ? UInt64.max : upSum.partialValue,
            currentDay: currentDay,
            resetReason: .none
        )
    }

    static func readCountersByInterface() -> [String: NetworkByteCounters] {
        var counters: [String: NetworkByteCounters] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return [:] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee,
                  let socketAddress = interface.ifa_addr,
                  Int32(socketAddress.pointee.sa_family) == AF_LINK,
                  let dataPointer = interface.ifa_data else {
                continue
            }

            let flags = interface.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0 else { continue }

            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            let name = String(cString: interface.ifa_name)
            counters[name] = NetworkByteCounters(
                interfaceName: name,
                inputBytes: UInt64(data.ifi_ibytes),
                outputBytes: UInt64(data.ifi_obytes)
            )
        }

        return counters
    }

    private func refreshInterfaces() {
        interfaces = NetworkInterfaceResolver.discoverInterfaces()
    }

    private func reselectInterfaceIfNeeded() {
        if let selectedInterfaceName, interfaces.contains(where: { $0.name == selectedInterfaceName }) {
            return
        }
        selectedInterfaceName = NetworkInterfaceResolver.preferredInterfaceName(from: interfaces)
        if let selectedInterfaceName {
            defaults.set(selectedInterfaceName, forKey: Self.selectedInterfaceDefaultsKey)
        }
        previousCounters = nil
        previousSampleAt = nil
    }

    private func interface(named name: String?) -> NetworkInterfaceResolver.InterfaceInfo? {
        guard let name else { return nil }
        return interfaces.first { $0.name == name }
    }

    private func loadPreferences() {
        selectedInterfaceName = defaults.string(forKey: Self.selectedInterfaceDefaultsKey)
        let today = Self.dayString(for: Date(), calendar: calendar)
        let savedDay = defaults.string(forKey: DefaultsKey.day)
        currentDay = today
        if savedDay == today {
            dailyDown = Self.uint64Default(forKey: DefaultsKey.down, defaults: defaults)
            dailyUp = Self.uint64Default(forKey: DefaultsKey.up, defaults: defaults)
        } else {
            dailyDown = 0
            dailyUp = 0
            persistDailyTotals()
        }
    }

    private func rollDayIfNeeded(_ now: Date) {
        let day = Self.dayString(for: now, calendar: calendar)
        guard day != currentDay else { return }
        currentDay = day
        dailyDown = 0
        dailyUp = 0
        previousCounters = nil
        previousSampleAt = nil
        persistDailyTotals()
    }

    private func persistDailyTotals() {
        defaults.set(currentDay, forKey: DefaultsKey.day)
        defaults.set(dailyDown, forKey: DefaultsKey.down)
        defaults.set(dailyUp, forKey: DefaultsKey.up)
    }

    private static func uint64Default(forKey key: String, defaults: UserDefaults) -> UInt64 {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return 0 }
        return number.uint64Value
    }

    private func seedBaselineAndPublish() {
        guard let selectedInterfaceName,
              let counters = Self.readCountersByInterface()[selectedInterfaceName] else {
            publish(down: 0, up: 0, now: Date())
            return
        }
        previousCounters = counters
        previousSampleAt = Date()
        publish(down: 0, up: 0, now: Date())
    }

    private func publish(down: Double, up: Double, now: Date) {
        sessionPeakDown = max(sessionPeakDown, down)
        sessionPeakUp = max(sessionPeakUp, up)
        history.append(NetworkThroughputPoint(downBytesPerSecond: down, upBytesPerSecond: up))
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }

        let snapshot = NetworkThroughputSnapshot(
            interface: interface(named: selectedInterfaceName),
            downBytesPerSecond: down,
            upBytesPerSecond: up,
            sessionPeakDownBytesPerSecond: sessionPeakDown,
            sessionPeakUpBytesPerSecond: sessionPeakUp,
            dailyDownBytes: dailyDown,
            dailyUpBytes: dailyUp,
            history: history,
            updatedAt: now
        )
        onUpdate?(snapshot)
        NotificationCenter.default.post(
            name: .networkThroughputDataUpdated,
            object: self,
            userInfo: ["snapshot": snapshot]
        )
    }
}
