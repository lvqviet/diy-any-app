import BatteryCore
import SwiftUI

/// Circular battery gauge with a marker at the charge limit. With Sailing Mode on, the gap
/// below the limit where charging stays paused is shaded.
struct BatteryRing: View {
    let percent: Int
    let settings: ChargeSettings
    let mode: ChargeMode
    let color: Color

    private var showsLimit: Bool { settings.limit < 100 && mode != .toppingUp }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line = max(5, size * 0.11)
            let radius = (size - line) / 2
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: line)
                if settings.sailingMode && showsLimit {
                    Circle()
                        .trim(from: fraction(settings.sailingThreshold), to: fraction(settings.limit))
                        .stroke(Color.teal.opacity(0.3), style: StrokeStyle(lineWidth: line, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                Circle()
                    .trim(from: 0, to: fraction(percent))
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if showsLimit {
                    Capsule()
                        .fill(Color.primary.opacity(0.85))
                        .frame(width: max(2, line * 0.3), height: line + 6)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(Double(settings.limit) * 3.6))
                }
                Text("\(percent)%")
                    .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
            }
            .frame(width: size, height: size)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(3)
        .animation(.easeInOut(duration: 0.6), value: percent)
        .animation(.easeInOut(duration: 0.3), value: settings)
        .help(showsLimit ? "Battery \(percent)%, limit \(settings.limit)%" : "Battery \(percent)%")
    }

    private func fraction(_ value: Int) -> CGFloat { CGFloat(max(0, min(100, value))) / 100 }
}
