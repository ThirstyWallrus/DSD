//
//  ConsistencyInfoSheet.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 11/3/25.
//


//
//  ConsistencyEfficiencySheets.swift
//  DynastyStatDrop
//
//  Compact helper sheet views used across expanded stat panels.
//  Purpose:
//    - Provide small informational sheets used by OffStatExpandedView,
//      DefStatExpandedView, and TeamStatExpandedView.
//    - Keep UI simple and consistent.
//    - No app state mutation here — purely presentational.
//

import SwiftUI

struct ConsistencyInfoSheet: View {
    let stdDev: Double
    let descriptor: String

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 40, height: 6)
                .padding(.top, 8)

            Text("Consistency")
                .font(.headline)
                .foregroundColor(.yellow)

            Text(descriptor)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))

            HStack(spacing: 16) {
                VStack {
                    Text(String(format: "%.2f", stdDev))
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    Text("Std Dev")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                VStack {
                    Text(consistencyVerb)
                        .font(.title3)
                        .bold()
                        .foregroundColor(consistencyColor)
                    Text("Interpretation")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.vertical, 8)

            Text("A lower standard deviation means more consistent weekly output. Use this to judge volatility and matchmaking risk.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer(minLength: 8)
        }
        .padding()
        .background(Color.black)
    }

    private var consistencyVerb: String {
        switch stdDev {
        case 0..<15: return "Steady"
        case 15..<35: return "Average"
        case 35..<55: return "Swingy"
        default: return "Boom-Bust"
        }
    }

    private var consistencyColor: Color {
        switch stdDev {
        case 0..<15: return .green
        case 15..<35: return .yellow
        case 35..<55: return .orange
        default: return .red
        }
    }
}

struct EfficiencyInfoSheet: View {
    let managementPercent: Double
    let pointsFor: Double
    let maxPointsFor: Double

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 40, height: 6)
                .padding(.top, 8)

            Text("Lineup Efficiency")
                .font(.headline)
                .foregroundColor(.yellow)

            HStack(spacing: 18) {
                VStack {
                    Text(String(format: "%.0f", pointsFor))
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    Text("Points For")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                VStack {
                    Text(String(format: "%.0f", maxPointsFor))
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    Text("Max Possible")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                VStack {
                    Text(String(format: "%.1f%%", managementPercent))
                        .font(.title2)
                        .bold()
                        .foregroundColor(managementPercentColor)
                    Text("Mgmt%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.vertical, 6)

            EfficiencyBar(ratio: managementPercent / 100.0, height: 12)
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)

            Text("Management% is (Points For) / (Max Possible). Higher is better — indicates how close the lineup came to theoretical maximum.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer(minLength: 8)
        }
        .padding()
        .background(Color.black)
    }

    private var managementPercentColor: Color {
        if managementPercent >= 75 { return .green }
        if managementPercent < 55 { return .red }
        return .yellow
    }

    private struct EfficiencyBar: View {
        let ratio: Double
        let height: CGFloat
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(LinearGradient(colors: [.red, .orange, .yellow, .green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(geo.size.width, geo.size.width * ratio)))
                        .animation(.easeInOut(duration: 0.25), value: ratio)
                }
            }
        }
    }
}
