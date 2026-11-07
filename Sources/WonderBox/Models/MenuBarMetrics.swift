import Foundation

struct MenuBarMetricOptions: Equatable, Sendable {
    static let cpuKey = "menuBarShowCPU"
    static let memoryKey = "menuBarShowMemory"
    static let onlyMetricsKey = "menuBarOnlyMetrics"
    static let powerKey = "menuBarShowPower"
    static let metricSeparator = "  "
    var menuBarVisible = true
    var showCPU = false
    var showMemory = false
    var showPower = false
    var onlyMetrics = false
    var isEnabled: Bool { menuBarVisible && (showCPU || showMemory || showPower) }
    /// The app icon stays when nothing else is in the status item, so the menu can still be opened.
    var showsAppIcon: Bool { !onlyMetrics || !(showCPU || showMemory || showPower) }
}

struct MenuBarResourceSample: Sendable {
    var sampledAt = Date()
    var uptime = ProcessInfo.processInfo.systemUptime
    var cpuTotal: UInt64?
    var cpuIdle: UInt64?
    var memoryFraction: Double?
    var systemPowerWatts: Double?
}

/// Stats `Double.usageColor` with its default zones: system blue through 60%, orange through 80%, red above.
enum MenuBarUsageColor: Equatable, Sendable {
    case blue, orange, red

    static func resolve(_ fraction: Double?) -> Self? {
        guard let fraction, fraction.isFinite, (0...1).contains(fraction) else { return nil }
        switch fraction {
        case 0...0.6: return .blue
        case 0.6...0.8: return .orange
        default: return .red
        }
    }
}

struct MenuBarMetricSnapshot: Equatable, Sendable {
    var cpu: Double?
    var memory: Double?
    var systemPowerWatts: Double?

    init(cpu: Double? = nil, memory: Double? = nil, systemPowerWatts: Double? = nil) {
        self.cpu = cpu
        self.memory = memory
        self.systemPowerWatts = systemPowerWatts
    }

    init(current: MenuBarResourceSample, previous: MenuBarResourceSample?) {
        memory = current.memoryFraction
        systemPowerWatts = current.systemPowerWatts
        guard let previous,
              (0.25...10).contains(current.uptime - previous.uptime),
              (0...10).contains(current.sampledAt.timeIntervalSince(previous.sampledAt)),
              let total = current.cpuTotal, let idle = current.cpuIdle,
              let oldTotal = previous.cpuTotal, let oldIdle = previous.cpuIdle,
              total > oldTotal, idle >= oldIdle, idle - oldIdle <= total - oldTotal else { return }
        cpu = Double((total - oldTotal) - (idle - oldIdle)) / Double(total - oldTotal)
    }

    func title(options: MenuBarMetricOptions) -> String {
        guard options.menuBarVisible else { return "" }
        var items: [String] = []
        if options.showCPU { items.append("CPU " + Self.percent(cpu)) }
        if options.showMemory { items.append("RAM " + Self.percent(memory)) }
        if options.showPower { items.append("PWR " + Self.watts(systemPowerWatts)) }
        return items.joined(separator: MenuBarMetricOptions.metricSeparator)
    }

    static func watts(_ value: Double?) -> String {
        guard let value, PowerReading.validated(value, source: "SMC · PSTR") != nil else { return "—" }
        return String(format: "%.1f W", value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite, (0...1).contains(value) else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }
}
