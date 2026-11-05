import SwiftUI

struct MenuBarMetricLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let style: MenuBarIconStyle
    let options: MenuBarMetricOptions
    let snapshot: MenuBarMetricSnapshot

    var body: some View {
        let title = snapshot.title(options: options)
        HStack(spacing: options.showsAppIcon && !title.isEmpty ? 5 : 0) {
            if options.showsAppIcon {
                Image(nsImage: MenuBarAppIcon.image(for: style))
            }
            if !title.isEmpty, let metrics = MenuBarMetricArtwork.image(options: options, snapshot: snapshot, appearance: appearance) {
                Image(nsImage: metrics).id("\(title)|\(tone(snapshot.cpu))|\(tone(snapshot.memory))|\(colorScheme)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.isEmpty ? "WonderBox" : "WonderBox · " + title)
    }

    private var appearance: NSAppearance {
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) ?? .currentDrawing()
    }

    private func tone(_ fraction: Double?) -> String {
        switch MenuBarUsageColor.resolve(fraction) {
        case .blue: "blue"
        case .orange: "orange"
        case .red: "red"
        case nil: "-"
        }
    }
}

enum MenuBarMetricArtwork {
    private static let labelFont = NSFont.systemFont(ofSize: 8, weight: .medium)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let columnGap: CGFloat = 12
    private static let columnPadding: CGFloat = 2

    static func image(options: MenuBarMetricOptions, snapshot: MenuBarMetricSnapshot, appearance: NSAppearance) -> NSImage? {
        let columns = columns(options: options, snapshot: snapshot, appearance: appearance)
        guard !columns.isEmpty else { return nil }
        let labelHeight = lineHeight(labelFont)
        let valueHeight = lineHeight(valueFont)
        let width = columns.reduce(0) { $0 + $1.width } + columnGap * CGFloat(columns.count - 1)
        let size = NSSize(width: ceil(width), height: ceil(labelHeight + valueHeight))
        guard size.width > 0, size.height > 0 else { return nil }
        let image = NSImage(size: size, flipped: true) { _ in
            var x: CGFloat = 0
            for column in columns {
                column.name.draw(with: NSRect(x: x, y: 0, width: column.width, height: labelHeight), options: [.usesLineFragmentOrigin])
                column.value.draw(with: NSRect(x: x, y: labelHeight, width: column.width, height: valueHeight), options: [.usesLineFragmentOrigin])
                x += column.width + columnGap
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private struct Column {
        var name: NSAttributedString
        var value: NSAttributedString
        var width: CGFloat
    }

    private static func columns(options: MenuBarMetricOptions, snapshot: MenuBarMetricSnapshot, appearance: NSAppearance) -> [Column] {
        guard options.menuBarVisible else { return [] }
        let label = resolved(.labelColor, appearance: appearance)
        let alignment = NSMutableParagraphStyle()
        alignment.alignment = .center
        func column(_ name: String, fraction: Double?) -> Column {
            let valueColor = MenuBarUsageColor.resolve(fraction).map { resolved($0.nsColor, appearance: appearance) } ?? label
            let nameText = NSAttributedString(string: name, attributes: [.font: labelFont, .foregroundColor: label, .paragraphStyle: alignment])
            let valueText = NSAttributedString(string: MenuBarMetricSnapshot.percent(fraction), attributes: [.font: valueFont, .foregroundColor: valueColor, .paragraphStyle: alignment])
            let width = max(measure(nameText), measure(valueText)) + columnPadding * 2
            return Column(name: nameText, value: valueText, width: width)
        }
        var columns: [Column] = []
        if options.showCPU { columns.append(column("CPU", fraction: snapshot.cpu)) }
        if options.showMemory { columns.append(column("RAM", fraction: snapshot.memory)) }
        return columns
    }

    private static func measure(_ text: NSAttributedString) -> CGFloat {
        ceil(text.boundingRect(with: NSSize(width: 200, height: 40), options: [.usesLineFragmentOrigin, .usesFontLeading]).width)
    }

    private static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private static func resolved(_ color: NSColor, appearance: NSAppearance) -> NSColor {
        var concrete = color
        appearance.performAsCurrentDrawingAppearance {
            concrete = color.usingColorSpace(.sRGB) ?? color
        }
        return concrete
    }
}

private extension MenuBarUsageColor {
    var nsColor: NSColor {
        switch self {
        case .blue: .systemBlue
        case .orange: .orange
        case .red: .red
        }
    }
}

struct MenuBarMetricSettings: View {
    var isEnabled = true
    @AppStorage(MenuBarMetricOptions.cpuKey) private var showCPU = false
    @AppStorage(MenuBarMetricOptions.memoryKey) private var showMemory = false
    @AppStorage(MenuBarMetricOptions.onlyMetricsKey) private var onlyMetrics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show CPU usage in menu bar", isOn: $showCPU)
                .accessibilityIdentifier("menubar.show-cpu")
            Toggle("Show memory usage in menu bar", isOn: $showMemory)
                .accessibilityIdentifier("menubar.show-memory")
            Toggle("Only show CPU and RAM", isOn: $onlyMetrics)
                .accessibilityIdentifier("menubar.only-metrics")
                .disabled(!(showCPU || showMemory))
            Text("CPU and RAM percentages refresh every 3 seconds, even with the main window closed. Turn off either value to save menu bar space. Only show CPU and RAM hides the app icon while a percentage is visible.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!isEnabled)
    }
}
