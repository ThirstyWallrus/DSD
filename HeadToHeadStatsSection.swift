//
//  HeadToHeadStatsSection.swift
//  DynastyStatDrop
//
//  Extracted Head-to-Head stats UI with per-match history list.
//  Cleaned: removed debug UI and console diagnostic logging.
//

import SwiftUI

struct HeadToHeadStatsSection: View {
    let user: TeamStanding
    let opp: TeamStanding
    let league: LeagueData

    // MARK: - Extracted computed properties / helpers to reduce body complexity

    private var h2hSummary: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        Self.getHeadToHeadAllTime(
            userOwnerId: user.ownerId,
            oppOwnerId: opp.ownerId,
            league: league
        )
    }

    private var h2hDetails: [H2HMatchDetail]? {
        Self.getHeadToHeadDetails(
            userOwnerId: user.ownerId,
            oppOwnerId: opp.ownerId,
            league: league
        )
    }

    private func sortedDetails(_ list: [H2HMatchDetail]) -> [H2HMatchDetail] {
        list.sorted { lhs, rhs in
            if lhs.seasonId != rhs.seasonId { return lhs.seasonId > rhs.seasonId }
            if lhs.week != rhs.week { return lhs.week > rhs.week }
            return lhs.matchupId > rhs.matchupId
        }
    }

    // MARK: - Body (broken into smaller subviews to aid the compiler)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBarView
            statsColumnsView
            matchHistoryView
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Subviews

    private var titleBarView: some View {
        HStack {
            Text("Head-to-Head Stats")
                .font(.headline.bold())
                .foregroundColor(.orange)
            Spacer()
        }
    }

    private var statsColumnsView: some View {
        // Pull precomputed values here with explicit type to avoid big expression in the main body
        let summary: (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) = h2hSummary

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .foregroundColor(.cyan)
                    .bold()
                statRow("Record vs Opponent", summary.record)
                // Use centralized mgmt color for the mgmt percent value
                HStack {
                    Text("Mgmt % vs Opponent")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.2f%%", summary.avgMgmtFor))
                        .foregroundColor(Color.mgmtPercentColor(summary.avgMgmtFor))
                        .bold()
                }
                .font(.caption)
                statRow("Avg Points/Game vs Opponent", String(format: "%.1f", summary.avgPF))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(opp.name)
                    .foregroundColor(.yellow)
                    .bold()
                // Use reverse format for opponent's record
                statRow("Record vs You", HeadToHeadStatsSection.reverseRecordString(summary.record))
                // Use centralized mgmt color for opponent mgmt percent display
                HStack {
                    Text("Mgmt % vs You")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.2f%%", summary.avgMgmtAgainst))
                        .foregroundColor(Color.mgmtPercentColor(summary.avgMgmtAgainst))
                        .bold()
                }
                .font(.caption)
                statRow("Avg Points/Game vs You", String(format: "%.1f", summary.avgPA))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var matchHistoryView: some View {
        Group {
            if let list = h2hDetails, !list.isEmpty {
                Divider().background(Color.white.opacity(0.06))
                Text("Match History")
                    .font(.subheadline.bold())
                    .foregroundColor(.white.opacity(0.9))

                // Compute sorted once and iterate by index to ensure unique ForEach ids
                let sorted = sortedDetails(list)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(sorted.indices, id: \.self) { idx in
                            let match = sorted[idx]
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("Season \(match.seasonId) • Week \(match.week)")
                                        .font(.caption.bold())
                                        .foregroundColor(.white.opacity(0.8))
                                    Text("Score: \(String(format: "%.1f", match.userPoints)) — \(String(format: "%.1f", match.oppPoints))")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(match.result)
                                        .font(.caption.bold())
                                        .foregroundColor(match.result == "W" ? .green : (match.result == "L" ? .red : .yellow))
                                    HStack {
                                        Text(String(format: "Mgmt: %.1f%%", match.userMgmtPct))
                                            .font(.caption2)
                                            .foregroundColor(Color.mgmtPercentColor(match.userMgmtPct))
                                        Text(String(format: "Opp: %.1f%%", match.oppMgmtPct))
                                            .font(.caption2)
                                            .foregroundColor(Color.mgmtPercentColor(match.oppMgmtPct))
                                    }
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.02)))
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxHeight: 220)
            } else {
                Text("No head-to-head matches on record.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // Replicate the small statRow helper previously in MatchupView
    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value)
                .foregroundColor(.orange)
                .bold()
        }
        .font(.caption)
    }

    // Local helper to reverse record string like "W-L" -> "L-W" and "W-L-T" -> "L-W-T"
    private static func reverseRecordString(_ str: String) -> String {
        let parts = str.split(separator: "-")
        if parts.count == 2 {
            return "\(parts[1])-\(parts[0])"
        } else if parts.count == 3 {
            return "\(parts[1])-\(parts[0])-\(parts[2])"
        }
        return str
    }

    // Same logic as prior: read all-time H2H from league.allTimeOwnerStats
    static func getHeadToHeadAllTime(userOwnerId: String, oppOwnerId: String, league: LeagueData) -> (record: String, avgMgmtFor: Double, avgPF: Double, avgMgmtAgainst: Double, avgPA: Double) {
        guard let userAgg = league.allTimeOwnerStats?[userOwnerId],
              let h2h = userAgg.headToHeadVs[oppOwnerId] else {
            return ("0-0", 0.0, 0.0, 0.0, 0.0)
        }
        return (h2h.record, h2h.avgMgmtFor, h2h.avgPointsFor, h2h.avgMgmtAgainst, h2h.avgPointsAgainst)
    }

    static func getHeadToHeadDetails(userOwnerId: String, oppOwnerId: String, league: LeagueData) -> [H2HMatchDetail]? {
        guard let userAgg = league.allTimeOwnerStats?[userOwnerId] else { return nil }
        return userAgg.headToHeadDetails?[oppOwnerId]
    }
}
