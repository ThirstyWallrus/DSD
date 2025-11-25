//
//  OffPositionBalanceDetailSheet.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 11/8/25.
//


// OffPositionBalanceDetailSheet.swift
// DynastyStatDrop
//
// Compact offensive balance detail sheet (gauges + tagline) with an optional
// "More info" DisclosureGroup that reveals the detailed derivation. Uses the
// shared PositionGauge/BalanceGauge/CircularProgressView from CircularProgressView.swift
// — decorative flame/glow/ice types have been removed from this file.
//

import SwiftUI

struct OffPositionBalanceDetailSheet: View {
    let positionPercents: [String: Double]
    let balancePercent: Double
    let tagline: String

    // Order for display
    private var orderedPositions: [String] { ["QB", "RB", "WR", "TE", "K"] }

    // Color mapping kept consistent with OffStatExpandedView
    private var positionColors: [String: Color] {
        [
            "QB": .red,
            "RB": .green,
            "WR": .blue,
            "TE": .yellow,
            "K": Color.purple
        ]
    }

    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(Color.white.opacity(0.15)).frame(width: 40, height: 6).padding(.top, 8)

            Text("Offensive Efficiency Spotlight")
                .font(.headline)
                .foregroundColor(.yellow)

            // Top row of gauges (QB, RB, WR) then (TE, Balance, K)
            HStack(spacing: 10) {
                PositionGauge(pos: "QB", pct: positionPercents["QB"] ?? 0, color: positionColors["QB"]!)
                PositionGauge(pos: "RB", pct: positionPercents["RB"] ?? 0, color: positionColors["RB"]!)
                PositionGauge(pos: "WR", pct: positionPercents["WR"] ?? 0, color: positionColors["WR"]!)
            }

            HStack(spacing: 10) {
                PositionGauge(pos: "TE", pct: positionPercents["TE"] ?? 0, color: positionColors["TE"]!)
                BalanceGauge(balance: balancePercent)
                PositionGauge(pos: "K", pct: positionPercents["K"] ?? 0, color: positionColors["K"]!)
            }

            Text(tagline)
                .font(.caption2)
                .foregroundColor(.yellow)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // More info disclosure — shows derivation, mean, SD, interpretation (identical to defensive sheet)
            DisclosureGroup {
                BalanceDetailContent(
                    orderedPositions: orderedPositions,
                    positionPercents: positionPercents,
                    balancePercent: balancePercent
                )
                .padding(.top, 8)
            } label: {
                HStack {
                    Spacer()
                    Text("More info")
                        .font(.caption2).bold()
                        .foregroundColor(.white.opacity(0.9))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal)

            Spacer(minLength: 8)
        }
        .padding(.bottom, 12)
        .background(Color.black)
    }
}