import AppKit
import BatteryCore
import Charts
import SwiftUI

/// Main window page: temperature chart of the last hour, current readings and fan speeds.
struct SensorsPage: View {
    @Environment(SensorsModel.self) private var model
    @State private var hoverDate: Date?

    var body: some View {
        Form {
            if let error = model.unavailable {
                Section { Notice(icon: "exclamationmark.circle.fill", tint: .red, text: error) }
            } else {
                Section {
                    chart
                        .frame(height: 240)
                        .padding(.vertical, 6)
                } header: {
                    Label("Temperature, last hour", systemImage: "thermometer.medium")
                } footer: {
                    Text("Each line is the average of that part's sensors. Sampled every 15 s in the background, every 5 s while this page is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(ThermalPart.allCases) { part in
                        LabeledContent {
                            Text(model.latest?.values[part].map(Self.nowText) ?? "–")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(Self.color(part)).frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                                Text(part.title)
                            }
                        }
                    }
                    LabeledContent("Thermal state") {
                        Text(Self.title(model.thermalState))
                            .foregroundStyle(model.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
                                             ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    }
                    .help("As reported by macOS; it throttles the Mac from Serious on")
                    ForEach(Array(model.fanSpeeds.enumerated()), id: \.offset) { index, rpm in
                        LabeledContent(model.fanSpeeds.count > 1 ? "Fan \(index + 1)" : "Fan") {
                            Text(rpm < 1 ? "Off" : "\(Int(rpm)) rpm")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Now", systemImage: "gauge.with.dots.needle.33percent")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sensors")
        .onWindowVisibilityChange { model.setWindowVisible("main", $0) }
    }

    private struct Point: Identifiable {
        let date: Date
        let part: ThermalPart
        let value: Double
        var id: String { "\(date.timeIntervalSince1970)-\(part.rawValue)" }
    }

    private var points: [Point] {
        model.history.flatMap { sample in
            ThermalPart.allCases.compactMap { part in
                sample.values[part].map { Point(date: sample.date, part: part, value: $0.average) }
            }
        }
    }

    /// Sample closest to the pointer.
    private var hovered: SensorsModel.Sample? {
        guard let hoverDate else { return nil }
        return model.history.min {
            abs($0.date.timeIntervalSince(hoverDate)) < abs($1.date.timeIntervalSince(hoverDate))
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Time", point.date), y: .value("°C", point.value))
                    .foregroundStyle(by: .value("Part", point.part.title))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            if let hovered {
                // Tooltip beside the line, on the side with more room, so it never covers the line.
                let onRight = hovered.date.timeIntervalSinceNow < -SensorsModel.window / 2
                RuleMark(x: .value("Time", hovered.date))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: onRight ? .trailing : .leading, alignment: .top, spacing: 8,
                                overflowResolution: .init(x: .disabled, y: .fit(to: .plot))) {
                        tooltip(hovered)
                    }
            }
        }
    }

    private var chart: some View {
        let titles = ThermalPart.allCases.map(\.title)
        let colors = ThermalPart.allCases.map(Self.color)
        let domain = Date(timeIntervalSinceNow: -SensorsModel.window)...Date()
        return chartContent
        .chartForegroundStyleScale(domain: titles, range: colors)
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxisLabel("°C")
        .chartXScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: Self.timeTicks(domain)) {
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() }
        }
        .chartOverlay { proxy in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let location) = phase { hoverDate = proxy.value(atX: location.x) } else { hoverDate = nil }
                }
        }
        .overlay {
            if model.history.count < 2 {
                Text("Collecting readings…").foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Temperature chart of the last hour")
    }

    private func tooltip(_ sample: SensorsModel.Sample) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sample.date.formatted(date: .omitted, time: .standard))
                .font(.caption.weight(.semibold))
            ForEach(ThermalPart.allCases) { part in
                if let value = sample.values[part]?.average {
                    HStack(spacing: 6) {
                        Circle().fill(Self.color(part)).frame(width: 7, height: 7)
                        Text(part.title)
                        Spacer(minLength: 12)
                        Text(Self.celsius(value)).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(8)
        .frame(width: 150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    static func celsius(_ value: Double) -> String { String(format: "%.0f °C", value) }

    static func nowText(_ reading: ThermalReading) -> String {
        "\(celsius(reading.average)) · hottest \(celsius(reading.hottest))"
    }

    /// Every 10 minutes, leaving out ticks near either end whose label would be cut off.
    static func timeTicks(_ domain: ClosedRange<Date>) -> [Date] {
        let step: TimeInterval = 600, margin: TimeInterval = 240
        let first = ((domain.lowerBound.timeIntervalSince1970 + margin) / step).rounded(.up) * step
        return stride(from: first, through: domain.upperBound.timeIntervalSince1970 - margin, by: step)
            .map(Date.init(timeIntervalSince1970:))
    }

    /// Categorical palette, checked for color-blind separation; each mode has its own steps.
    static func color(_ part: ThermalPart) -> Color {
        let (light, dark): (UInt32, UInt32) = switch part {
        case .cpu: (0x2a78d6, 0x3987e5)
        case .gpu: (0xeb6834, 0xd95926)
        case .battery: (0x1baf7a, 0x199e70)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }

    static func title(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
