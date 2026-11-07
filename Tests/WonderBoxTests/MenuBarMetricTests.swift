import AppKit
import SwiftUI
import XCTest
@testable import WonderBox

final class MenuBarMetricTests: XCTestCase {
    func testIndependentDisplayCombinationsAndUnknownValues() {
        let value = MenuBarMetricSnapshot(cpu: 0.12, memory: 0.64)
        XCTAssertEqual(value.title(options: .init()), "")
        XCTAssertEqual(value.title(options: .init(showCPU: true)), "CPU 12%")
        XCTAssertEqual(value.title(options: .init(showMemory: true)), "RAM 64%")
        XCTAssertEqual(value.title(options: .init(showCPU: true, showMemory: true)), "CPU 12%  RAM 64%")
        XCTAssertEqual(value.title(options: .init(menuBarVisible: false, showCPU: true, showMemory: true)), "")
        XCTAssertEqual(MenuBarMetricSnapshot(memory: 0.64).title(options: .init(showCPU: true, showMemory: true)), "CPU —  RAM 64%")
        for invalid in [Double.nan, .infinity, -0.01, 1.01] {
            XCTAssertEqual(MenuBarMetricSnapshot(cpu: invalid).title(options: .init(showCPU: true)), "CPU —")
        }
        XCTAssertEqual(MenuBarMetricSnapshot(cpu: 0, memory: 1).title(options: .init(showCPU: true, showMemory: true)), "CPU 0%  RAM 100%")
        XCTAssertTrue(MenuBarMetricOptions().showsAppIcon)
        XCTAssertTrue(MenuBarMetricOptions(onlyMetrics: true).showsAppIcon)
        XCTAssertFalse(MenuBarMetricOptions(showCPU: true, onlyMetrics: true).showsAppIcon)
        XCTAssertFalse(MenuBarMetricOptions(showMemory: true, onlyMetrics: true).showsAppIcon)
        XCTAssertFalse(MenuBarMetricOptions(showPower: true, onlyMetrics: true).showsAppIcon)
        XCTAssertTrue(MenuBarMetricOptions(showPower: true).showsAppIcon)
        XCTAssertTrue(MenuBarMetricOptions(showCPU: true, showMemory: true).showsAppIcon)
    }

    func testUsageColorMatchesStatsZonesAndPaintsThePercentage() throws {
        XCTAssertEqual(MenuBarUsageColor.resolve(0), .blue)
        XCTAssertEqual(MenuBarUsageColor.resolve(0.6), .blue)
        XCTAssertEqual(MenuBarUsageColor.resolve(0.6.nextUp), .orange)
        XCTAssertEqual(MenuBarUsageColor.resolve(0.8), .orange)
        XCTAssertEqual(MenuBarUsageColor.resolve(0.8.nextUp), .red)
        XCTAssertEqual(MenuBarUsageColor.resolve(1), .red)
        XCTAssertNil(MenuBarUsageColor.resolve(nil))
        for invalid in [Double.nan, .infinity, -0.01, 1.01] {
            XCTAssertNil(MenuBarUsageColor.resolve(invalid))
        }

        let aqua = try XCTUnwrap(NSAppearance(named: .aqua))
        let low = try XCTUnwrap(MenuBarMetricArtwork.image(options: .init(showCPU: true), snapshot: .init(cpu: 0.12), appearance: aqua))
        let mid = try XCTUnwrap(MenuBarMetricArtwork.image(options: .init(showMemory: true), snapshot: .init(memory: 0.7), appearance: aqua))
        let high = try XCTUnwrap(MenuBarMetricArtwork.image(options: .init(showCPU: true), snapshot: .init(cpu: 0.91), appearance: aqua))
        let both = try XCTUnwrap(MenuBarMetricArtwork.image(options: .init(showCPU: true, showMemory: true), snapshot: .init(cpu: 0.91, memory: 0.12), appearance: aqua))
        let unknown = try XCTUnwrap(MenuBarMetricArtwork.image(options: .init(showCPU: true), snapshot: .init(), appearance: aqua))
        XCTAssertFalse(low.isTemplate)
        XCTAssertFalse(high.isTemplate)
        XCTAssertEqual(usageColors(in: low, appearance: aqua), [.blue])
        XCTAssertEqual(usageColors(in: mid, appearance: aqua), [.orange])
        XCTAssertEqual(usageColors(in: high, appearance: aqua), [.red])
        XCTAssertEqual(usageColors(in: both, appearance: aqua), [.blue, .red])
        XCTAssertGreaterThan(both.size.height, both.size.width / 4, "Each percentage sits under its label")
        XCTAssertGreaterThan(both.size.width, 60)
        XCTAssertLessThan(both.size.width, 100)
        XCTAssertEqual(usageColors(in: unknown, appearance: aqua), [])
        XCTAssertNil(MenuBarMetricArtwork.image(options: .init(), snapshot: .init(cpu: 0.9), appearance: aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let darkLow = try XCTUnwrap(MenuBarMetricArtwork.image(options: .init(showCPU: true), snapshot: .init(cpu: 0.12), appearance: dark))
        XCTAssertEqual(usageColors(in: darkLow, appearance: dark), [.blue])
        XCTAssertGreaterThan(brightNeutralPixels(in: darkLow), 8)
        XCTAssertEqual(brightNeutralPixels(in: low), 0)
    }

    func testPowerArtworkPreservesStackedMetricsAndNeutralWatts() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let snapshot = MenuBarMetricSnapshot(cpu: 0.91, memory: 0.12, systemPowerWatts: 18.26)
            let power = try XCTUnwrap(MenuBarMetricArtwork.image(options: .init(showPower: true), snapshot: snapshot, appearance: appearance))
            let usage = try XCTUnwrap(MenuBarMetricArtwork.image(options: .init(showCPU: true, showMemory: true), snapshot: snapshot, appearance: appearance))
            let combined = try XCTUnwrap(MenuBarMetricArtwork.image(options: .init(showCPU: true, showMemory: true, showPower: true), snapshot: snapshot, appearance: appearance))
            XCTAssertGreaterThan(power.size.width, 30)
            XCTAssertEqual(power.size.height, usage.size.height)
            XCTAssertGreaterThan(combined.size.width, usage.size.width + power.size.width)
            XCTAssertEqual(usageColors(in: power, appearance: appearance), [])
            XCTAssertEqual(usageColors(in: combined, appearance: appearance), [.blue, .red])
            XCTAssertNil(MenuBarMetricArtwork.image(options: .init(menuBarVisible: false, showPower: true), snapshot: snapshot, appearance: appearance))
        }
    }

    func testPowerDisplayCombinationsAndInvalidReadings() {
        let snapshot = MenuBarMetricSnapshot(cpu: 0.12, memory: 0.64, systemPowerWatts: 18.26)
        for cpu in [false, true] {
            for memory in [false, true] {
                for power in [false, true] {
                    let options = MenuBarMetricOptions(showCPU: cpu, showMemory: memory, showPower: power)
                    let expected = [(cpu, "CPU 12%"), (memory, "RAM 64%"), (power, "PWR 18.3 W")]
                        .filter { $0.0 }.map { $0.1 }.joined(separator: "  ")
                    XCTAssertEqual(snapshot.title(options: options), expected)
                    XCTAssertEqual(options.isEnabled, cpu || memory || power)
                    var hidden = options
                    hidden.menuBarVisible = false
                    XCTAssertFalse(hidden.isEnabled)
                    XCTAssertEqual(snapshot.title(options: hidden), "")
                }
            }
        }
        let powerOnly = MenuBarMetricOptions(showPower: true)
        XCTAssertEqual(MenuBarMetricSnapshot().title(options: powerOnly), "PWR —")
        for invalid in [Double.nan, .infinity, -.infinity, -0.01, 2000.01] {
            XCTAssertEqual(MenuBarMetricSnapshot(systemPowerWatts: invalid).title(options: powerOnly), "PWR —")
        }
        XCTAssertEqual(MenuBarMetricSnapshot(systemPowerWatts: 0).title(options: powerOnly), "PWR 0.0 W")
        XCTAssertEqual(MenuBarMetricSnapshot(systemPowerWatts: 2000).title(options: powerOnly), "PWR 2000.0 W")
        let sample = MenuBarResourceSample(systemPowerWatts: 18.26)
        XCTAssertEqual(MenuBarMetricSnapshot(current: sample, previous: nil).systemPowerWatts, 18.26,
                       "System power must not depend on a CPU baseline")
        XCTAssertNil(MenuBarMetricSnapshot(current: MenuBarResourceSample(), previous: sample).systemPowerWatts,
                     "A failed sensor read must clear the previous value, not leave stale watts")
    }

    func testCPUUsesAggregateDeltasAndMemoryMatchesTheExistingUsedFraction() {
        let before = sample(1, total: 100, idle: 80)
        let after = sample(4, total: 300, idle: 180)
        XCTAssertEqual(MenuBarMetricSnapshot(current: after, previous: before), .init(cpu: 0.5, memory: 0.64))
        let memory = MemoryBreakdown(total: 100, app: 30, wired: 20, compressed: 14, cached: 25)
        XCTAssertEqual(memory.usedFraction, 0.64)
        XCTAssertNil(MenuBarMetricSnapshot(current: after, previous: nil).cpu)
        XCTAssertEqual(MenuBarMetricSnapshot(current: after, previous: nil).memory, 0.64)
    }

    func testResetMissingCountersClockChangesAndSleepGapsDoNotLookIdle() {
        let before = sample(1, total: 100, idle: 80)
        for current in [sample(4, total: 100, idle: 80), sample(4, total: 90, idle: 80),
                        sample(4, total: 200, idle: 70), sample(4, total: 200, idle: 190),
                        sample(20, total: 200, idle: 90), sample(0, total: 200, idle: 90),
                        sample(1.01, total: 200, idle: 90), sample(4, total: nil, idle: nil)] {
            XCTAssertNil(MenuBarMetricSnapshot(current: current, previous: before).cpu)
        }
        var clockReset = sample(4, total: 200, idle: 100)
        clockReset.sampledAt = Date(timeIntervalSince1970: 0)
        XCTAssertNil(MenuBarMetricSnapshot(current: clockReset, previous: before).cpu)
        XCTAssertEqual(MenuBarMetricSnapshot(current: sample(4, total: 200, idle: 180), previous: before).cpu, 0)
    }

    @MainActor
    func testPreferencesDefaultOffPersistIndependentlyAndSurviveHiddenMenuBar() throws {
        let suite = "WonderBoxTests.MenuMetrics.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cpu = AppStorage(wrappedValue: false, MenuBarMetricOptions.cpuKey, store: defaults)
        let memory = AppStorage(wrappedValue: false, MenuBarMetricOptions.memoryKey, store: defaults)
        let onlyMetrics = AppStorage(wrappedValue: false, MenuBarMetricOptions.onlyMetricsKey, store: defaults)
        let power = AppStorage(wrappedValue: false, MenuBarMetricOptions.powerKey, store: defaults)
        XCTAssertFalse(cpu.wrappedValue)
        XCTAssertFalse(memory.wrappedValue)
        XCTAssertFalse(onlyMetrics.wrappedValue)
        XCTAssertFalse(power.wrappedValue)
        XCTAssertFalse(MenuBarMetricOptions().showPower)
        cpu.wrappedValue = true
        XCTAssertFalse(memory.wrappedValue)
        XCTAssertFalse(onlyMetrics.wrappedValue)
        onlyMetrics.wrappedValue = true
        memory.wrappedValue = true
        power.wrappedValue = true
        cpu.wrappedValue = false
        defaults.set(false, forKey: "showMenuBar")
        XCTAssertFalse(AppStorage(wrappedValue: false, MenuBarMetricOptions.cpuKey, store: defaults).wrappedValue)
        XCTAssertTrue(AppStorage(wrappedValue: false, MenuBarMetricOptions.memoryKey, store: defaults).wrappedValue)
        XCTAssertTrue(AppStorage(wrappedValue: false, MenuBarMetricOptions.powerKey, store: defaults).wrappedValue)
        defaults.set(true, forKey: "showMenuBar")
        XCTAssertTrue(memory.wrappedValue)
        XCTAssertTrue(power.wrappedValue)
        power.wrappedValue = false
        XCTAssertTrue(memory.wrappedValue)
    }

    @MainActor
    func testDisabledDefaultsDoNotStartBackgroundSampling() async {
        let monitor = MenuBarMetricMonitor(read: { _ in XCTFail("Disabled sampler ran"); return MenuBarResourceSample() }, notifications: NotificationCenter())
        monitor.configure(.init())
        monitor.configure(.init(menuBarVisible: false, showCPU: true, showMemory: true, showPower: true))
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(monitor.isRunning)
    }

    @MainActor
    func testCPUSamplerPrimesThenUsesThreeSecondIntervalsWithoutWindowDependency() async {
        let feed = MenuMetricFeed()
        let monitor = MenuBarMetricMonitor(read: { await feed.read($0) }, sleep: {
            await feed.recordInterval($0)
            try await Task.sleep(for: .milliseconds(15))
        }, notifications: NotificationCenter())
        monitor.configure(.init(showCPU: true))
        defer { monitor.configure(.init()) }
        await eventually { monitor.snapshot.cpu == 0.25 }
        XCTAssertNil(monitor.snapshot.memory)
        let intervals = await feed.intervals
        XCTAssertEqual(intervals.first, 1)
        XCTAssertTrue(intervals.dropFirst().allSatisfy { $0 == 3 })
        let model = AppModel()
        model.stopMonitoring()
        XCTAssertTrue(monitor.isRunning, "Main-window monitoring must not own the status item timer")
        let options = await feed.options
        XCTAssertTrue(options.allSatisfy { $0.showCPU && !$0.showMemory && !$0.showPower })
    }

    @MainActor
    func testMemoryOnlySkipsCPUAndRepeatedConfigurationDoesNotDuplicateTimer() async {
        let feed = MenuMetricFeed()
        let monitor = MenuBarMetricMonitor(read: { await feed.read($0) }, sleep: {
            await feed.recordInterval($0)
            try await Task.sleep(for: .seconds(60))
        }, notifications: NotificationCenter())
        let options = MenuBarMetricOptions(showMemory: true)
        monitor.configure(options)
        defer { monitor.configure(.init()) }
        await eventually { monitor.snapshot.memory == 0.64 }
        for _ in 0..<20 { monitor.configure(options) }
        let requests = await feed.options
        let intervals = await feed.intervals
        XCTAssertEqual(requests, [options])
        XCTAssertEqual(intervals, [3])
        XCTAssertNil(monitor.snapshot.cpu)
        XCTAssertNil(monitor.snapshot.systemPowerWatts)
    }

    @MainActor
    func testPowerOnlySamplingStopsWhenHiddenAndResumesWithANewReading() async {
        let feed = MenuMetricFeed()
        let monitor = MenuBarMetricMonitor(read: { await feed.read($0) }, sleep: {
            await feed.recordInterval($0)
            try await Task.sleep(for: .seconds(60))
        }, notifications: NotificationCenter())
        let enabled = MenuBarMetricOptions(showPower: true)
        monitor.configure(enabled)
        defer { monitor.configure(.init()) }
        await eventually { monitor.snapshot.systemPowerWatts == 18.26 }
        XCTAssertNil(monitor.snapshot.cpu)
        XCTAssertNil(monitor.snapshot.memory)
        let intervals = await feed.intervals
        XCTAssertEqual(intervals, [3])
        let requests = await feed.options
        XCTAssertEqual(requests, [enabled])
        monitor.configure(.init(menuBarVisible: false, showPower: true))
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(monitor.snapshot, .init())
        monitor.configure(enabled)
        await eventually { monitor.snapshot.systemPowerWatts == 18.26 }
        monitor.setSleeping(true)
        XCTAssertEqual(monitor.snapshot, .init())
        monitor.setSleeping(false)
        await eventually { monitor.snapshot.systemPowerWatts == 18.26 }
        monitor.configure(.init())
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(monitor.snapshot, .init())
    }

    @MainActor
    func testDisablingMetricsDiscardsInFlightResult() async {
        let gate = MenuMetricGate()
        let monitor = MenuBarMetricMonitor(read: { await gate.read($0) }, notifications: NotificationCenter())
        monitor.configure(.init(showPower: true))
        await eventuallyAsync { await gate.pendingCount == 1 }
        monitor.configure(.init())
        await gate.finishAll()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(monitor.snapshot, .init())
    }

    @MainActor
    func testSleepClearsValuesAndWakeStartsANewBaselineOnlyWhenEnabled() async {
        let feed = MenuMetricFeed(), notifications = NotificationCenter()
        let monitor = MenuBarMetricMonitor(read: { await feed.read($0) }, sleep: { _ in try await Task.sleep(for: .seconds(60)) }, notifications: notifications)
        monitor.configure(.init(showCPU: true, showMemory: true, showPower: true))
        defer { monitor.configure(.init()) }
        await eventually { monitor.snapshot.memory == 0.64 }
        XCTAssertEqual(monitor.snapshot.systemPowerWatts, 18.26)
        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        await eventually { !monitor.isRunning }
        XCTAssertEqual(monitor.snapshot, .init())
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        await eventually { monitor.snapshot.memory == 0.64 }
        XCTAssertNil(monitor.snapshot.cpu)
        monitor.configure(.init(menuBarVisible: false, showCPU: true))
        monitor.setSleeping(true)
        monitor.setSleeping(false)
        XCTAssertFalse(monitor.isRunning)
    }

    @MainActor
    func testSleepingTaskDoesNotRetainItsMonitor() async {
        var monitor: MenuBarMetricMonitor? = MenuBarMetricMonitor(read: { _ in MenuBarResourceSample(memoryFraction: 0.5) },
                                                                 sleep: { _ in try await Task.sleep(for: .seconds(60)) }, notifications: NotificationCenter())
        weak var reference = monitor
        defer { reference = nil }
        monitor?.configure(.init(showMemory: true))
        await eventually { monitor?.snapshot.memory == 0.5 }
        monitor = nil
        XCTAssertNil(reference)
    }

    @MainActor
    func testLiveReadOnlySamplerGetsCPUAndMemoryWithoutOpeningAWindow() async {
        let monitor = MenuBarMetricMonitor(notifications: NotificationCenter())
        monitor.configure(.init(showCPU: true, showMemory: true))
        defer { monitor.configure(.init()) }
        await eventually { monitor.snapshot.cpu != nil && monitor.snapshot.memory != nil }
        XCTAssertTrue((0...1).contains(monitor.snapshot.cpu ?? -1))
        XCTAssertTrue((0...1).contains(monitor.snapshot.memory ?? -1))
    }

    @MainActor
    func testLiveSystemPowerReaderPublishesValidWattsOrUnavailable() async {
        let completed = MenuMetricFeed()
        let monitor = MenuBarMetricMonitor(sleep: {
            await completed.recordInterval($0)
            try await Task.sleep(for: .seconds(60))
        }, notifications: NotificationCenter())
        monitor.configure(.init(showPower: true))
        defer { monitor.configure(.init()) }
        await eventuallyAsync { await !completed.intervals.isEmpty }
        XCTAssertNil(monitor.snapshot.cpu)
        XCTAssertNil(monitor.snapshot.memory)
        if let watts = monitor.snapshot.systemPowerWatts {
            XCTAssertNotNil(PowerReading.validated(watts, source: "SMC · PSTR"))
        } else {
            XCTAssertEqual(monitor.snapshot.title(options: .init(showPower: true)), "PWR —")
        }
    }

    @MainActor
    func testSettingsRendersPreferenceChangesWithoutChangingLayout() throws {
        let suite = "WonderBoxTests.MenuMetricSettings.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = NSHostingView(rootView: MenuBarMetricSettings().padding(16).background(Color.panelBackground)
            .defaultAppStorage(defaults).preferredColorScheme(.light))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 190), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.frame = window.contentView!.bounds
        defer { window.contentView = nil }
        settle(host)
        func rendered() throws -> Data {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }
        let before = try rendered(), frame = host.frame
        defaults.set(true, forKey: MenuBarMetricOptions.cpuKey); settle(host)
        let cpuOnly = try rendered()
        XCTAssertNotEqual(before, cpuOnly)
        defaults.set(false, forKey: MenuBarMetricOptions.cpuKey)
        defaults.set(true, forKey: MenuBarMetricOptions.memoryKey); settle(host)
        XCTAssertNotEqual(cpuOnly, try rendered())
        XCTAssertEqual(host.frame, frame)
        XCTAssertFalse(defaults.bool(forKey: MenuBarMetricOptions.cpuKey))
        XCTAssertTrue(defaults.bool(forKey: MenuBarMetricOptions.memoryKey))
        let memoryOnly = try rendered()
        defaults.set(true, forKey: MenuBarMetricOptions.powerKey); settle(host)
        XCTAssertNotEqual(memoryOnly, try rendered())
        XCTAssertTrue(defaults.bool(forKey: MenuBarMetricOptions.powerKey))
        XCTAssertEqual(host.frame, frame)
        if ProcessInfo.processInfo.environment["WONDERBOX_RENDER_PREVIEWS"] == "1" {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/wonderbox-menu-metric-settings.png"))
        }
    }

    private func usageColors(in image: NSImage, appearance: NSAppearance) -> Set<MenuBarUsageColor> {
        let scale: CGFloat = 2
        let pixelsWide = Int(ceil(image.size.width * scale))
        let pixelsHigh = Int(ceil(image.size.height * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale))
        NSGraphicsContext.restoreGraphicsState()
        let targets = [MenuBarUsageColor.blue, .orange, .red].map { tone -> (MenuBarUsageColor, (CGFloat, CGFloat, CGFloat)) in
            var color = NSColor.black
            appearance.performAsCurrentDrawingAppearance {
                switch tone {
                case .blue: color = NSColor.systemBlue
                case .orange: color = NSColor.orange
                case .red: color = NSColor.red
                }
                color = color.usingColorSpace(.sRGB) ?? color
            }
            return (tone, (color.redComponent, color.greenComponent, color.blueComponent))
        }
        var scores: [MenuBarUsageColor: Int] = [:]
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.6 else { continue }
                let sample = (pixel.redComponent, pixel.greenComponent, pixel.blueComponent)
                let nearest = targets.min { distance(sample, $0.1) < distance(sample, $1.1) }
                guard let nearest, distance(sample, nearest.1) < 0.08 else { continue }
                scores[nearest.0, default: 0] += 1
            }
        }
        return Set(scores.filter { $0.value >= 8 }.keys)
    }

    private func brightNeutralPixels(in image: NSImage) -> Int {
        let scale: CGFloat = 2
        let pixelsWide = Int(ceil(image.size.width * scale))
        let pixelsHigh = Int(ceil(image.size.height * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale))
        NSGraphicsContext.restoreGraphicsState()
        var count = 0
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.6 else { continue }
                if min(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.75 { count += 1 }
            }
        }
        return count
    }

    private func distance(_ lhs: (CGFloat, CGFloat, CGFloat), _ rhs: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        let red = lhs.0 - rhs.0, green = lhs.1 - rhs.1, blue = lhs.2 - rhs.2
        return red * red + green * green + blue * blue
    }

    private func sample(_ time: Double, total: UInt64?, idle: UInt64?) -> MenuBarResourceSample {
        MenuBarResourceSample(sampledAt: Date(timeIntervalSince1970: time), uptime: time, cpuTotal: total, cpuIdle: idle, memoryFraction: 0.64)
    }
    @MainActor
    private func eventually(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for sampler", file: file, line: line)
    }
    @MainActor
    private func eventuallyAsync(_ condition: () async -> Bool) async {
        for _ in 0..<400 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for sample request")
    }
    @MainActor
    private func settle(_ host: NSView) {
        for _ in 0..<4 { RunLoop.main.run(until: Date().addingTimeInterval(0.025)); host.layoutSubtreeIfNeeded() }
    }
}

private actor MenuMetricFeed {
    var options: [MenuBarMetricOptions] = []
    var intervals: [TimeInterval] = []
    func recordInterval(_ interval: TimeInterval) { intervals.append(interval) }
    func read(_ options: MenuBarMetricOptions) -> MenuBarResourceSample {
        self.options.append(options)
        let tick = options.showCPU ? UInt64(self.options.count) : 0
        return MenuBarResourceSample(sampledAt: Date(timeIntervalSince1970: Double(self.options.count)), uptime: Double(self.options.count),
                                     cpuTotal: options.showCPU ? tick * 100 : nil, cpuIdle: options.showCPU ? tick * 75 : nil,
                                     memoryFraction: options.showMemory ? 0.64 : nil,
                                     systemPowerWatts: options.showPower ? 18.26 : nil)
    }
}

private actor MenuMetricGate {
    var pending: [CheckedContinuation<MenuBarResourceSample, Never>] = []
    var pendingCount: Int { pending.count }
    func read(_ options: MenuBarMetricOptions) async -> MenuBarResourceSample {
        await withCheckedContinuation { pending.append($0) }
    }
    func finishAll() {
        let waiting = pending
        pending.removeAll()
        waiting.forEach { $0.resume(returning: MenuBarResourceSample(memoryFraction: 0.64, systemPowerWatts: 18.26)) }
    }
}
