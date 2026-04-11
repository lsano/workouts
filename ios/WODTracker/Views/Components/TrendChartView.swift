import SwiftUI

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct TrendChartView: View {
    let dataPoints: [TrendDataPoint]
    let color: Color
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with latest value and change
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let latest = dataPoints.last {
                    Text(String(format: "%.0f", latest.value))
                        .font(.title3)
                        .fontWeight(.bold)
                }
                if let change = percentChange {
                    Text(changeLabel(change))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(change >= 0 ? .green : .red)
                }
            }

            // Canvas chart
            Canvas { context, size in
                guard dataPoints.count >= 2 else { return }

                let maxValue = dataPoints.map(\.value).max() ?? 1
                let minValue = dataPoints.map(\.value).min() ?? 0
                let range = max(maxValue - minValue, 1)
                let barWidth = size.width / CGFloat(dataPoints.count) * 0.7
                let spacing = size.width / CGFloat(dataPoints.count)
                let chartBottom = size.height - 20 // leave room for date labels
                let chartHeight = chartBottom - 4

                // Draw bars
                for (index, point) in dataPoints.enumerated() {
                    let normalised = (point.value - minValue) / range
                    let barHeight = chartHeight * normalised
                    let x = spacing * CGFloat(index) + (spacing - barWidth) / 2
                    let y = chartBottom - barHeight

                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    let roundedBar = Path(roundedRect: rect, cornerRadius: 3)
                    context.fill(roundedBar, with: .color(color.opacity(0.35)))
                }

                // Draw line overlay
                var linePath = Path()
                for (index, point) in dataPoints.enumerated() {
                    let normalised = (point.value - minValue) / range
                    let x = spacing * CGFloat(index) + spacing / 2
                    let y = chartBottom - chartHeight * normalised
                    if index == 0 {
                        linePath.move(to: CGPoint(x: x, y: y))
                    } else {
                        linePath.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(linePath, with: .color(color), lineWidth: 2)

                // Draw dots on line
                for (index, point) in dataPoints.enumerated() {
                    let normalised = (point.value - minValue) / range
                    let x = spacing * CGFloat(index) + spacing / 2
                    let y = chartBottom - chartHeight * normalised
                    let dotRect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                    context.fill(Circle().path(in: dotRect), with: .color(color))
                }

                // Draw date labels
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "M/d"
                let labelStep = max(1, dataPoints.count / 5)
                for index in stride(from: 0, to: dataPoints.count, by: labelStep) {
                    let x = spacing * CGFloat(index) + spacing / 2
                    let dateText = dateFormatter.string(from: dataPoints[index].date)
                    context.draw(
                        Text(dateText).font(.system(size: 9)).foregroundColor(.secondary),
                        at: CGPoint(x: x, y: size.height - 6)
                    )
                }
            }
            .frame(height: 160)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private var percentChange: Double? {
        guard dataPoints.count >= 2 else { return nil }
        let first = dataPoints[dataPoints.count - 2].value
        guard first > 0 else { return nil }
        let last = dataPoints.last!.value
        return ((last - first) / first) * 100
    }

    private func changeLabel(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f", change))%"
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let points = (0..<7).map { i in
        TrendDataPoint(
            date: calendar.date(byAdding: .day, value: -6 + i, to: today)!,
            value: Double.random(in: 20...80)
        )
    }
    TrendChartView(dataPoints: points, color: .blue, title: "Volume")
        .padding()
}
