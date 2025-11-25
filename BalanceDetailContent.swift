//
//  BalanceDetailContent.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 11/8/25.
//


import SwiftUI

/// BalanceDetailContent
/// Shared detailed explanatory content used by both OffPositionBalanceDetailSheet and DefensiveBalanceInfoSheet.
/// Shows per-position values, mean, SD, recomputed balance, and interpretation bullets.
/// Keeps wording & formulas identical for offense/defense so the only difference between the sheets is
/// which positions & colors are supplied by the caller.
struct BalanceDetailContent: View {
    let orderedPositions: [String]
    let positionPercents: [String: Double]
    let balancePercent: Double

    private var valuesOrdered: [Double] { orderedPositions.map { positionPercents[$0] ?? 0.0 } }

    private var mean: Double {
        guard !valuesOrdered.isEmpty else { return 0 }
        return valuesOrdered.reduce(0, +) / Double(valuesOrdered.count)
    }

    private var variance: Double {
        guard !valuesOrdered.isEmpty else { return 0 }
        return valuesOrdered.reduce(0) { $0 + pow($1 - mean, 2) } / Double(valuesOrdered.count)
    }

    private var sd: Double { sqrt(variance) }

    private var recomputedBalance: Double {
        guard mean > 0 else { return 0 }
        return (sd / mean) * 100
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How the balance is derived")
                .font(.subheadline).bold()
                .foregroundColor(.white)

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

            VStack(alignment: .leading, spacing: 8) {
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
                        .font(.caption2).bold()
                        .foregroundColor(balancePercent < 8 ? .green : (balancePercent < 16 ? .yellow : .red))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal)
            .background(Color.white.opacity(0.02))
            .cornerRadius(8)

            Divider().background(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 8) {
                Text("How to interpret the numbers")
                    .font(.subheadline).bold()
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 6) {
                    Text("• balance < 8% — Very balanced: usage is well distributed among positions.")
                    Text("• balance 8–16% — Moderately balanced: one group may take more of the load.")
                    Text("• balance > 16% — Unbalanced: one or two positions dominate usage; consider roster or matchup adjustments.")
                }
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
            }
        }
    }
}