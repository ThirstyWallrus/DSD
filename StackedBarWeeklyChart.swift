// StackedBarWeeklyChart.swift
// DynastyStatDrop
//
// Created by Dynasty Stat Drop on 10/28/25.
//
// Reusable stacked bar chart for weekly position breakdowns.
// - Each bar = one week, segments colored per position
// - Supports tooltip on tap
// - Always fits all bars in available width
// - Custom horizontal grid lines and chart top value
//
// NEW: Optional aggregation mode to collapse multi-position segments into
// two-side stacks (Offense / Defense). When enabled, each weekly bar will
// contain exactly two blocks: Offense (red) and Defense (blue). A small
// legend appears below the chart when aggregation is enabled.
//
// This version measures the left axis label width at runtime and aligns the
// labels so their trailing edge sits just left of the chart content area,
// preventing the first bar from overlapping the labels on all devices,
// dynamic type sizes, and localizations.
//
// IMPORTANT: This version preserves the pre-change behavior of showing only
// weeks that have data (total > 0). Even when aggregated, empty/unplayed
// weeks are filtered out so the chart shows only weeks played.
//
import SwiftUI

// PreferenceKey used to measure the maximum width of the y-axis labels.
// Use a static let defaultValue (immutable) to avoid Swift concurrency diagnostics.
private struct MaxLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct StackedBarWeeklyChart: View {
    public struct WeekBarData: Identifiable {
        public let id: Int // week number, 1-based
        public let segments: [Segment]
        public struct Segment: Identifiable {
            public let id: String
            public let position: String // canonical position (QB, RB, etc) or custom token
            public let value: Double
        }
        public let total: Double
        public init(id: Int, segments: [Segment]) {
            self.id = id
            self.segments = segments
            self.total = segments.reduce(0) { $0 + $1.value }
        }
    }
   
    public let weekBars: [WeekBarData] // oldest to newest (left to right)
    public let positionColors: [String: Color] // normalized position -> Color (used when not aggregating)
    public let showPositions: Set<String> // which positions to display per bar (used when not aggregating)
    public let gridIncrement: Double // increment for grid lines (e.g., 25 or 50)
    public let barSpacing: CGFloat // space between bars
    public let tooltipFont: Font // font for tooltip
    public let showWeekLabels: Bool // show week numbers below bars
   
    // When true, collapse position segments into Offense (red) and Defense (blue).
    public let aggregateToOffDef: Bool

    // New: explicit legend control:
    // - showAggregateLegend: if true, show the simple Offense / Defense legend (colored dots + labels).
    // - showOffensePositionsLegend: if true, show the QB/RB/WR/TE/K colored position legend row.
    // - showDefensePositionsLegend: if true, show the DL/LB/DB colored position legend row.
    // Callers should set these so that only the intended view shows the intended legend.
    public let showAggregateLegend: Bool
    public let showOffensePositionsLegend: Bool
    public let showDefensePositionsLegend: Bool

    @State private var tappedWeek: Int? = nil

    // Measured max width of left axis labels (updated at runtime via preference)
    @State private var measuredLabelWidth: CGFloat = 0

    public init(
        weekBars: [WeekBarData],
        positionColors: [String: Color],
        showPositions: Set<String>,
        gridIncrement: Double,
        barSpacing: CGFloat = 4,
        tooltipFont: Font = .caption2.bold(),
        showWeekLabels: Bool = true,
        aggregateToOffDef: Bool = false,
        // legend flags default to false. Callers (Team/Off/Def views) will pass explicit values to control which legends appear where.
        showAggregateLegend: Bool = false,
        showOffensePositionsLegend: Bool = false,
        showDefensePositionsLegend: Bool = false
    ) {
        self.weekBars = weekBars
        self.positionColors = positionColors
        self.showPositions = showPositions
        self.gridIncrement = gridIncrement
        self.barSpacing = barSpacing
        self.tooltipFont = tooltipFont
        self.showWeekLabels = showWeekLabels
        self.aggregateToOffDef = aggregateToOffDef
        self.showAggregateLegend = showAggregateLegend
        self.showOffensePositionsLegend = showOffensePositionsLegend
        self.showDefensePositionsLegend = showDefensePositionsLegend
    }

    // Helper: return a color for a normalized position using the provided positionColors, falling back to sensible defaults.
    private func colorForPosition(_ pos: String) -> Color {
        let norm = PositionNormalizer.normalize(pos)
        if let c = positionColors[norm] { return c }
        switch norm {
        case PositionNormalizer.normalize("QB"): return .red
        case PositionNormalizer.normalize("RB"): return .green
        case PositionNormalizer.normalize("WR"): return .blue
        case PositionNormalizer.normalize("TE"): return .yellow
        case PositionNormalizer.normalize("K"):  return Color.purple
        case PositionNormalizer.normalize("DL"): return .orange
        case PositionNormalizer.normalize("LB"): return Color.purple.opacity(0.7)
        case PositionNormalizer.normalize("DB"): return .pink
        default: return .gray
        }
    }

    // Canonical offense / defense position lists used for legends
    private let offensePositionsLegend: [String] = ["QB","RB","WR","TE","K"]
    private let defensePositionsLegend: [String] = ["DL","LB","DB"]

    public var body: some View {
        VStack(spacing: 16) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // Always filter out weeks with zero total so we only display weeks played
                let filteredWeekBars = weekBars.filter { $0.total > 0 }
                let barCount = filteredWeekBars.count

                // Compute chart top / grid lines early so we can size left axis space dynamically.
                let maxTotal = filteredWeekBars.map { $0.total }.max() ?? 0.0
                let effectiveChartTop = maxTotal > 0 ? ceil(maxTotal / gridIncrement) * gridIncrement : gridIncrement
                let gridLines = stride(from: gridIncrement, through: effectiveChartTop, by: gridIncrement).map { $0 }

                // Build label strings (include "0")
                let yLabelStrings = ([0] + gridLines.map { Int($0) }).map { String($0) }

                // Default safety values while measurement hasn't occurred
                let measured = max(measuredLabelWidth, CGFloat(20)) // avoid zero
                // gap between labels trailing edge and bars
                let labelGap: CGFloat = 8
                // compute left padding from measured label width + gap
                let leftPadding: CGFloat = measured + labelGap
                // keep a very small right padding so bars can extend almost to chart edge
                let rightPadding: CGFloat = 6

                // Compute bar sizing using the measured left padding and small right padding
                let effectiveWidth = w - leftPadding - rightPadding
                // Protect against zero/negative effective width.
                let adjustedEffectiveWidth = max(0, effectiveWidth)
                let totalSpacing = CGFloat(max(0, barCount - 1)) * barSpacing
                let barWidth = barCount > 0 ? max(2, (adjustedEffectiveWidth - totalSpacing) / CGFloat(barCount)) : 0

                ZStack {
                    // Hidden measurer: place offscreen/invisible Texts to measure maximum label width.
                    // We place this in the ZStack so it gets laid out but does not affect visible layout.
                    VStack(spacing: 0) {
                        ForEach(yLabelStrings, id: \.self) { s in
                            Text(s)
                                .font(.caption2)
                                .fixedSize() // ensure intrinsic size measured
                                .background(
                                    GeometryReader { g in
                                        Color.clear
                                            .preference(key: MaxLabelWidthKey.self, value: g.size.width)
                                    }
                                )
                                .hidden() // keep measured but not visible
                        }
                    }
                    .onPreferenceChange(MaxLabelWidthKey.self) { val in
                        // Use main thread update for animation stability
                        DispatchQueue.main.async {
                            measuredLabelWidth = max(measuredLabelWidth, val)
                        }
                    }

                    // Bottom line at 0
                    let y0 = h
                    Path { p in
                        p.move(to: CGPoint(x: leftPadding, y: y0))
                        p.addLine(to: CGPoint(x: w - rightPadding, y: y0))
                    }
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                   
                    // 0 label (aligned to axis trailing edge)
                    // Place label inside a frame with measured width and right-aligned so trailing edge
                    // sits near the chart content edge.
                    // Compute label center such that trailing edge of the measured frame is just left of leftPadding.
                    // labelCenterX = leftPadding - measured/2 - trailingInset
                    let labelTrailingInset: CGFloat = 2 // small inset to avoid touching stroke; tune if needed
                    let labelCenterX = leftPadding - (measured / 2) - labelTrailingInset

                    Text("0")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.40))
                        .frame(width: measured, alignment: .trailing)
                        .position(x: labelCenterX, y: y0 - 8)

                    // Grid lines and labels
                    ForEach(gridLines, id: \.self) { lineValue in
                        let y = h - CGFloat(lineValue / effectiveChartTop) * h
                        Path { p in
                            p.move(to: CGPoint(x: leftPadding, y: y))
                            p.addLine(to: CGPoint(x: w - rightPadding, y: y))
                        }
                        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 2]))

                        // Numeric grid label: right-aligned in a frame of measured width, positioned so
                        // its trailing edge is just left of the bar area (leftPadding).
                        Text("\(Int(lineValue))")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.40))
                            .frame(width: measured, alignment: .trailing)
                            .position(x: labelCenterX, y: y - 2)
                    }
                   
                    // Bars
                    HStack(alignment: .bottom, spacing: barSpacing) {
                        ForEach(filteredWeekBars) { weekBar in
                            VStack(spacing: 0) {
                                VStack(spacing: 0) {
                                    Spacer()
                                    if aggregateToOffDef {
                                        // Aggregate segments into Offense/Defense totals
                                        let (offValue, defValue) = aggregateOffDef(from: weekBar)
                                        // Render Offense (red) at bottom, Defense (blue) above it
                                        if offValue > 0 {
                                            let segHeight = CGFloat(offValue / effectiveChartTop) * h
                                            Rectangle()
                                                .fill(Color.red)
                                                .frame(height: segHeight)
                                                .cornerRadius(segHeight > 8 ? 3 : 1)
                                        }
                                        if defValue > 0 {
                                            let segHeight = CGFloat(defValue / effectiveChartTop) * h
                                            Rectangle()
                                                .fill(Color.blue)
                                                .frame(height: segHeight)
                                                .cornerRadius(segHeight > 8 ? 3 : 1)
                                        }
                                    } else {
                                        ForEach(weekBar.segments.filter { showPositions.contains($0.position) }.reversed()) { seg in
                                            let segHeight = CGFloat(seg.value / effectiveChartTop) * h
                                            Rectangle()
                                                .fill(positionColors[seg.position] ?? Color.gray)
                                                .frame(height: segHeight)
                                                .cornerRadius(segHeight > 8 ? 3 : 1)
                                        }
                                    }
                                }
                                .frame(width: barWidth, height: h)
                                .contentShape(Rectangle())
                                .onTapGesture { tappedWeek = weekBar.id }
                               
                                if showWeekLabels {
                                    Text("Wk\(weekBar.id)")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.45))
                                        .frame(height: 16)
                                }
                            }
                            .frame(width: barWidth)
                        }
                    }
                    // Use padding rather than hard offset so that layout/clipping plays nicely with safe areas.
                    .padding(.leading, leftPadding)
                    .padding(.trailing, rightPadding)
                   
                    // Tooltip
                    if let t = tappedWeek, let weekBar = weekBars.first(where: { $0.id == t }) {
                        // We need the index in filteredWeekBars (not full weekBars)
                        let idx = filteredWeekBars.firstIndex(where: { $0.id == t }) ?? 0
                        // Compute center x of the selected bar within the drawable area
                        let x = leftPadding + CGFloat(idx) * (barWidth + barSpacing) + barWidth / 2
                        let tooltipY: CGFloat = {
                            // Place above the bar's top
                            let barTotal = weekBar.total
                            return h - CGFloat(barTotal / effectiveChartTop) * h - 40
                        }()
                        TooltipView(weekBar: weekBar, positionColors: tooltipColors(), font: tooltipFont, aggregateToOffDef: aggregateToOffDef)
                            // clamp tooltip inside the chart area using left/right paddings
                            .position(x: min(max(leftPadding + 40, x), w - rightPadding - 40), y: max(30, tooltipY))
                            .transition(.opacity.combined(with: .scale))
                            .onTapGesture { tappedWeek = nil }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: tappedWeek)
            }
            .frame(height: 140)
           
            // Legend (flexible):
            // Controlled explicitly by new legend flags so callers decide what to show.
            VStack(alignment: .leading, spacing: 8) {
                if aggregateToOffDef {
                    // Aggregate header (Offense / Defense) — show only if caller requested it.
                    if showAggregateLegend {
                        HStack(spacing: 16) {
                            HStack(spacing: 6) {
                                Circle().fill(Color.red).frame(width: 10, height: 10)
                                Text("Offense").foregroundColor(.red).font(.caption2).bold()
                            }
                            HStack(spacing: 6) {
                                Circle().fill(Color.blue).frame(width: 10, height: 10)
                                Text("Defense").foregroundColor(.blue).font(.caption2).bold()
                            }
                            Spacer()
                        }
                    }

                    // Offense positions legend row (QB, RB, WR, TE, K) — only if explicitly requested
                    if showOffensePositionsLegend {
                        HStack(spacing: 12) {
                            ForEach(offensePositionsLegend, id: \.self) { pos in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(colorForPosition(pos))
                                        .frame(width: 10, height: 10)
                                    Text(pos)
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                }
                            }
                            Spacer()
                        }
                    }

                    // Defense positions legend row (DL, LB, DB) — only if explicitly requested
                    if showDefensePositionsLegend {
                        HStack(spacing: 12) {
                            ForEach(defensePositionsLegend, id: \.self) { pos in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(colorForPosition(pos))
                                        .frame(width: 10, height: 10)
                                    Text(pos)
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                }
                            }
                            Spacer()
                        }
                    }
                } else {
                    // Not aggregated: show legends when requested OR when showPositions indicates their presence.
                    let normalizedShow = Set(showPositions.map { PositionNormalizer.normalize($0) })
                    let offenseSet = Set(offensePositionsLegend.map { PositionNormalizer.normalize($0) })
                    let defenseSet = Set(defensePositionsLegend.map { PositionNormalizer.normalize($0) })

                    // Offense legend row (only positions requested or present)
                    if showOffensePositionsLegend || !normalizedShow.intersection(offenseSet).isEmpty {
                        HStack(spacing: 12) {
                            ForEach(offensePositionsLegend.filter { normalizedShow.contains(PositionNormalizer.normalize($0)) || showOffensePositionsLegend }, id: \.self) { pos in
                                // Only include items that are requested or actually present in showPositions
                                if normalizedShow.contains(PositionNormalizer.normalize(pos)) || showOffensePositionsLegend {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(colorForPosition(pos))
                                            .frame(width: 10, height: 10)
                                        Text(pos)
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            Spacer()
                        }
                    }

                    // Defense legend row (only positions requested or present)
                    if showDefensePositionsLegend || !normalizedShow.intersection(defenseSet).isEmpty {
                        HStack(spacing: 12) {
                            ForEach(defensePositionsLegend.filter { normalizedShow.contains(PositionNormalizer.normalize($0)) || showDefensePositionsLegend }, id: \.self) { pos in
                                if normalizedShow.contains(PositionNormalizer.normalize(pos)) || showDefensePositionsLegend {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(colorForPosition(pos))
                                            .frame(width: 10, height: 10)
                                        Text(pos)
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
   
    // MARK: Helpers
   
    // Aggregate a weekBar's segments into (offense, defense) totals.
    // Uses canonical normalization of segment.position (expects "QB","RB","WR","TE","K","DL","LB","DB" etc),
    // but will treat unknown tokens as offense by default.
    private func aggregateOffDef(from weekBar: WeekBarData) -> (Double, Double) {
        var off = 0.0
        var def = 0.0
        let offSet: Set<String> = ["QB","RB","WR","TE","K"]
        let defSet: Set<String> = ["DL","LB","DB"]
        for seg in weekBar.segments {
            let pos = PositionNormalizer.normalize(seg.position)
            if offSet.contains(pos) {
                off += seg.value
            } else if defSet.contains(pos) {
                def += seg.value
            } else {
                // Unknown positions: attempt to infer (treat as offense by default)
                off += seg.value
            }
        }
        return (off, def)
    }
   
    // Tooltip color mapping for aggregated mode or normal mode
    private func tooltipColors() -> [String: Color] {
        if aggregateToOffDef {
            return ["OFF": .red, "DEF": .blue]
        }
        return positionColors
    }
}
private struct TooltipView: View {
    let weekBar: StackedBarWeeklyChart.WeekBarData
    let positionColors: [String: Color]
    let font: Font
    let aggregateToOffDef: Bool
   
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wk\(weekBar.id) Breakdown")
                .font(font)
                .foregroundColor(.yellow)
            if aggregateToOffDef {
                // Show aggregated offense/defense totals
                let (off, def) = aggregateOffDef(from: weekBar)
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                    Text("Offense: \(String(format: "%.2f", off))")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.blue).frame(width: 10, height: 10)
                    Text("Defense: \(String(format: "%.2f", def))")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                Text("Total: \(String(format: "%.2f", off + def))")
                    .font(.caption2.bold())
                    .foregroundColor(.cyan)
            } else {
                ForEach(weekBar.segments) { seg in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(positionColors[seg.position] ?? .gray)
                            .frame(width: 10, height: 10)
                        Text("\(seg.position): \(String(format: "%.1f", seg.value))")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                }
                Text("Total: \(String(format: "%.1f", weekBar.total))")
                    .font(.caption2.bold())
                    .foregroundColor(.cyan)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.90)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.22), lineWidth: 1))
        .foregroundColor(.white)
    }
   
    private func aggregateOffDef(from weekBar: StackedBarWeeklyChart.WeekBarData) -> (Double, Double) {
        var off = 0.0
        var def = 0.0
        let offSet: Set<String> = ["QB","RB","WR","TE","K"]
        let defSet: Set<String> = ["DL","LB","DB"]
        for seg in weekBar.segments {
            let pos = PositionNormalizer.normalize(seg.position)
            if offSet.contains(pos) {
                off += seg.value
            } else if defSet.contains(pos) {
                def += seg.value
            } else {
                off += seg.value
            }
        }
        return (off, def)
    }
}
