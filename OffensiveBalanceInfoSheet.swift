//
//  OffensiveBalanceInfoSheet.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 11/6/25.
//


//
//  OffensiveBalanceInfoSheet.swift
//  DynastyStatDrop
//
//  Created by Copilot on 2025-11-06.
//
//  Purpose:
//   A focused explanatory pop-up for the "Balance" center of the Offensive Efficiency Spotlight.
//   - Explains how the balance % is computed (coefficient-of-variation style).
//   - Explains what a position Mgmt% (position usage efficiency) means.
//   - Shows a step-by-step numeric example using the passed-in position percents.
//   - Designed to be presented as a sheet (.sheet(...)) from OffStatExpandedView.
//
//  Usage (example):
//   @State private var showPositionBalanceInfo = false
//   Button { showPositionBalanceInfo = true } label: { Text("What is Balance?") }
//   .sheet(isPresented: $showPositionBalanceInfo) {
//       OffensiveBalanceInfoSheet(positionPercents: positionMgmtPercents, balancePercent: positionBalancePercent)
//           .presentationDetents([.fraction(0.45)])
//   }
//

import SwiftUI

struct OffensiveBalanceInfoSheet: View {
    // Per-position management percents (0..100)
    // Expected keys: "QB","RB","WR","TE","K"
    let positionPercents: [String: Double]
    // Precomputed balance percent (for display/highlighting) — we also recompute locally to show steps
    let balancePercent: Double
    let tagline: String
    
    
    init(positionPercents:[String: Double], balancedPercent: Double, tagline: String = "") {
        self.positionPercents = positionPercents
        // FIX: Assign the passed-in balancedPercent to the stored property balancePercent (was mistakenly self-assigning)
        self.balancePercent = balancedPercent
        self.tagline = tagline
    }
    // Order and default labels
    private let orderedPositions: [String] = ["QB", "RB", "WR", "TE", "K"]

    // Local computed values used for the example breakdown
    private var valuesOrdered: [Double] {
        orderedPositions.map { positionPercents[$0] ?? 0.0 }
    }
    private var mean: Double {
        guard !valuesOrdered.isEmpty else { return 0 }
        return valuesOrdered.reduce(0, +) / Double(valuesOrdered.count)
    }
    private var variance: Double {
        guard !valuesOrdered.isEmpty else { return 0 }
        return valuesOrdered.reduce(0) { $0 + pow($1 - mean, 2) } / Double(valuesOrdered.count)
    }
    private var sd: Double {
        sqrt(variance)
    }
    // Recompute the balance (coefficient of variation * 100) for demonstration
    private var recomputedBalance: Double {
        guard mean > 0 else { return 0 }
        return (sd / mean) * 100
    }

    // Friendly formatted numbers
    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Drag handle
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 40, height: 6)
                    .padding(.top, 8)

                Text("Offensive Balance — How the score is derived")
                    .font(.headline)
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)

                // Short summary
                Text("Balance shows how evenly usage (position Management %) is distributed across your offense. Lower values mean usage is more even; higher values indicate one or more positions are carrying a disproportionate share.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)

                Divider().background(Color.white.opacity(0.12))

                // Quick definitions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key definitions")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Position Mgmt% (usage efficiency):")
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                        Text("  The percent shown for a position (e.g., RB = 72%) indicates how efficiently you deployed players at that position relative to the positional maximum for the weeks considered. It's computed as (points scored by starters at that position) ÷ (max possible points for those starter slots) × 100.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Balance % (spread of usage):")
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                        Text("  We measure balance as the coefficient of variation (CV) across the position Mgmt% values, expressed as a percent:\n\n    balance% = (standard deviation of position Mgmt%) / (mean position Mgmt%) × 100\n\n  Lower = more balanced; Higher = more skewed toward particular positions.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal)

                Divider().background(Color.white.opacity(0.12))

                // Detailed numeric example using the passed-in values
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example (derived from current position values):")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)

                    // Show the per-position values
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(orderedPositions, id: \.self) { pos in
                            HStack {
                                Text(pos)
                                    .font(.caption2).bold()
                                    .foregroundColor(.white)
                                    .frame(width: 36, alignment: .leading)
                                Text("\(fmt(positionPercents[pos] ?? 0.0)) %")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.95))
                                Spacer()
                                // Helpful indicator if this position is notably above/below mean
                                if mean > 0 {
                                    let diff = (positionPercents[pos] ?? 0) - mean
                                    Text(diff >= 0 ? "+\(fmt(diff)) vs mean" : "\(fmt(diff)) vs mean")
                                        .font(.caption2)
                                        .foregroundColor(diff > 8 ? .green : (diff < -8 ? .orange : .gray))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    // Show computational steps
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Mean (average Mgmt%)")
                                .font(.caption2).foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Text("\(fmt(mean)) %")
                                .font(.caption2).bold().foregroundColor(.white)
                        }
                        HStack {
                            Text("Standard deviation (SD)")
                                .font(.caption2).foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Text("\(fmt(sd))")
                                .font(.caption2).bold().foregroundColor(.white)
                        }
                        HStack {
                            Text("Balance (SD / Mean × 100)")
                                .font(.caption2).foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Text("\(fmt(recomputedBalance)) %")
                                .font(.caption2).bold().foregroundColor(balancePercent < 8 ? .green : (balancePercent < 16 ? .yellow : .red))
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(8)
                }
                .padding(.horizontal)

                Divider().background(Color.white.opacity(0.12))

                // Interpretive guidance
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to interpret the numbers")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("• balance < 8% — Very balanced: usage is well distributed across positions.")
                        Text("• balance 8–16% — Moderately balanced: a couple positions take more of the load.")
                        Text("• balance > 16% — Unbalanced: one or two positions dominate usage; consider roster or lineup adjustments.")
                    }
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))

                    Text("Position Mgmt% examples:")
                        .font(.caption2).bold()
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("• RB at 80% — RB starters scored 80% of the maximum possible RB points. That indicates RB usage is efficient.")
                        Text("• WR at 45% — WR usage is inefficient (many bench/rotational choices or missed start opportunities).")
                        Text("• A big gap between RB and WR suggests the roster relies heavily on one position group.")
                    }
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal)

                Divider().background(Color.white.opacity(0.12))

                // Quick tips & CTA
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick tips")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    Text("• Use this insight to decide whether to chase players who improve a weak position or trade away surplus depth at a dominating position.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                    Text("• Balance is not inherently 'good' or 'bad' — context matters. A superstar RB that produces huge points may raise balance but still win you weeks.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal)

                Spacer(minLength: 12)
            }
            .padding(.bottom, 16)
        }
        .background(Color.black.edgesIgnoringSafeArea(.bottom))
    }
}

// MARK: - Preview with sample data (useful as the example before integrating)
struct OffensiveBalanceInfoSheet_Previews: PreviewProvider {
    static var sample: [String: Double] = [
        "QB": 88.0,
        "RB": 75.0,
        "WR": 62.0,
        "TE": 55.0,
        "K": 70.0
    ]

    static var previews: some View {
        OffensiveBalanceInfoSheet(positionPercents: sample, balancedPercent: {
            // compute same CV-based balance for preview
            let vals = ["QB","RB","WR","TE","K"].map { sample[$0] ?? 0.0 }
            let mean = vals.reduce(0, +) / Double(vals.count)
            let variance = vals.reduce(0) { $0 + pow($1 - mean, 2) } / Double(vals.count)
            let sd = sqrt(variance)
            return mean > 0 ? (sd / mean) * 100 : 0
        }())
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
    }
}
