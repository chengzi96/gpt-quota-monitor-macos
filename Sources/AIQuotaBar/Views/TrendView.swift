import Charts
import SwiftUI

struct TrendView: View {
    @EnvironmentObject private var store: QuotaStore
    let poolID: QuotaPoolID
    @State private var hoveredSample: UsageSample?

    private var samples: [UsageSample] { store.samples(for: poolID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("过去 7 天")
                    .font(DesignTokens.bodyFont)
                    .foregroundStyle(DesignTokens.secondaryText)
                Spacer()
                Text("本周额度 · 本机记录")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.tertiaryText.opacity(0.86))
            }

            if samples.count >= 2 {
                Chart {
                    ForEach(samples) { sample in
                        AreaMark(
                            x: .value("日期", sample.date),
                            y: .value("消耗", sample.usedPercent)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [poolID.accent.opacity(0.14), poolID.accent.opacity(0.004)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("日期", sample.date),
                            y: .value("消耗", sample.usedPercent)
                        )
                        .foregroundStyle(poolID.accent.opacity(0.88))
                        .lineStyle(StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                    }

                    if let hoveredSample {
                        RuleMark(x: .value("选中日期", hoveredSample.date))
                            .foregroundStyle(DesignTokens.primaryText.opacity(0.08))
                            .lineStyle(StrokeStyle(lineWidth: 1))

                        PointMark(
                            x: .value("选中日期", hoveredSample.date),
                            y: .value("选中消耗", hoveredSample.usedPercent)
                        )
                        .foregroundStyle(poolID.accent)
                        .symbolSize(18)
                        .annotation(position: .top, spacing: 4) {
                            Text("\(QuotaFormatters.shortDate(hoveredSample.date)) · 本周最高消耗 \(QuotaFormatters.percent(hoveredSample.usedPercent))")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DesignTokens.primaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .glassEffect(
                                    .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                    }
                }
                .chartXScale(domain: trendDomain)
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard let plotAnchor = proxy.plotFrame else {
                                        hoveredSample = nil
                                        return
                                    }
                                    let plotFrame = geometry[plotAnchor]
                                    let localX = location.x - plotFrame.origin.x
                                    guard localX >= 0, localX <= plotFrame.width,
                                          let date: Date = proxy.value(atX: localX) else {
                                        hoveredSample = nil
                                        return
                                    }
                                    hoveredSample = nearestSample(to: date)
                                case .ended:
                                    hoveredSample = nil
                                }
                            }
                    }
                }
                .frame(height: 50)
                .accessibilityLabel("\(poolID.displayName) 本周额度过去七天消耗趋势")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                    Text("记录至少 2 天后生成趋势")
                }
                .font(DesignTokens.smallFont)
                .foregroundStyle(DesignTokens.tertiaryText.opacity(0.86))
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            }
        }
    }

    private func nearestSample(to date: Date) -> UsageSample? {
        samples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private var trendDomain: ClosedRange<Date> {
        let end = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -6, to: end) ?? end
        return start...end
    }
}
